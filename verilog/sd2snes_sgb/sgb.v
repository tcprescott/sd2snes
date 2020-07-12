`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:
// Engineer:
//
// Create Date:
// Design Name:
// Module Name:    sgb
// Project Name:
// Target Devices:
// Tool versions:
// Description:
//
// Dependencies:
//
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//
//////////////////////////////////////////////////////////////////////////////////
`include "config.vh"

module sgb(
  input         RST,
  output        CPU_RST,
  input         CLK,

  // MMIO interface
  //input         ENABLE,
  input         SNES_RD_start,
  input         SNES_WR_end,
  input  [23:0] SNES_ADDR,
  input  [7:0]  DATA_IN,
  output [7:0]  DATA_OUT,

  // ROM interface
  input         ROM_BUS_RDY,
  output        ROM_BUS_RRQ,
  output        ROM_BUS_WRQ,
  output        ROM_BUS_WORD,
  output [23:0] ROM_BUS_ADDR,
  input  [7:0]  ROM_BUS_RDDATA,
  output [7:0]  ROM_BUS_WRDATA,
  output        ROM_FREE_SLOT,

  // Audio interface
  output [19:0] APU_DAT,
  output        APU_CLK_EDGE,

  // RTC interface
  output [55:0] RTC_DAT,
  input  [55:0] RTC_DAT_IN,
  input         RTC_DAT_WE,
  input         RTC_DAT_RD,
  
  // MBC interface
  input  [3:0]  MAPPER,
  input  [23:0] SAVERAM_MASK,
  input  [23:0] ROM_MASK,

  // Halt inferface
  input         HLT_REQ,
  output        HLT_RSP,
  
  // Debug state
  input         MCU_RRQ,
  input         MCU_WRQ,
  input  [18:0] MCU_ADDR,
  input  [7:0]  MCU_DATA_IN,
  output        MCU_RSP,
  output [7:0]  MCU_DATA_OUT,

  // Configuration
  input  [7:0]  reg_group_in,
  input  [7:0]  reg_index_in,
  input  [7:0]  reg_value_in,
  input  [7:0]  reg_invmask_in,
  input         reg_we_in,
  input  [7:0]  reg_read_in,
  output [7:0]  config_data_out,

  output [11:0] DBG_ADDR,
  input  [7:0]  DBG_CHEAT_DATA_IN,
  input  [7:0]  DBG_MAIN_DATA_IN,
  
  output        DBG
);

integer i;

//-------------------------------------------------------------------
// DESCRIPTION
//-------------------------------------------------------------------

// This is an HDL implementation of the Super Game Boy 2 SNES cartridge.
// It is tailored to SD2SNES so that (1) it is easy to maintain along
// with the other cart implementations and (2) improve the chance
// it will fit on the MK2.
//
// Super Game Boy 2
// ----------------
// The SGB2 is a SNES cartridge with the following components
// which allows for a GB game to execute and generate pixel data for the
// SNES to DMA and render with its own PPU.  Audio generated by
// the GB APU plays through the L-R analog pins on the cartridge bus.
//
// SGB2-CPU - Unified GB CPU, APU, and PPU chip with integrated 8KB VRAM.
// WRAM     - 8KB GB work RAM
// ICD2     - SGB<->SNES interface chip
// SYS-SGB2 - SNES boot and execution ROM
// CIC      - protection/lockout chip
//
// Like the original GB, the SGB2 has a 8-bit Z80/8080 ISA compatible CPU, 
// a APU supporting 4 channel audio, and a PPU capable of generating
// pixel data for a 160x144 2b gray-scale screen.
//
// In addition to the standard GB hardware the SGB2 also contains the
// SYS-SGB2 and ICD2 chips.  These provide the code and interface by
// which the SNES CPU boots and communicates with the GB hardware in
// order to copy and render the GB video output via the SNES PPU.
// 
// The ICD2 provides an interface to the GB domain via the GB system bus
// (ICD2, WRAM, GB cart bus) as well as an interface to the SNES domain
// via the SNES cart bus.  Row buffers within the ICD2 store digital pixel
// output data from the GB CPU which the SNES typically accesses via DMA.
//
// The SNES ROM provides several standard features including: boot support,
// overlays, palette control, joypad reads, etc.  More generally it
// implements a packet-based protocol which enables communication with
// the SGB2's ICD2.
//
// Clocks/Rates:
// 4.194304 MHz fast/machine clock
// 1.048576 MHz slow/system/bus clock
// 9198 KHz Horizontal Freq
// 59.73 Hz Vertical Freq
//
// Instructions and bus activity takes 1 or more bus clocks.
//
// CARTS
// -----
// The SD2SNES must implement not only the SGB2 but also any logic
// supported by the GB cart.  The mappers reside in this file.  Supported
// types are: MBC0, MBC1, MBC2, MBC3, and MBC5.  It's not clear if any
// GB-enabled GBC carts used MBC5, though.
//
// SD2SNES
// -------
// The SD2SNES MK2 has the following resources available for implementing
// the SGB2:
//
// 16MB PSRAM - GB cart, GB WRAM, GB SaveRAM, GB boot ROM
// 512KB RAM  - SNES ROM
// 32KB BRAM  - VRAM, OAM, HRAM, SNESCMD, MSU/DAC
// (FPGA)
// 1 PLL      - mult=7, div=2 -> 24 MHz * 7 / 2 = 84 MHz.  Skip 1 after 737 -> 83.8861789 MHz vs an equivalent 88.608 MHz on a real SGB2.
//
// Address Maps
// ------------
// GAMEBOY
//   0000-3FFF   16KB ROM Bank 00     (in cartridge, fixed at bank 00)           // PSRAM 000000-7FFFFF
//   4000-7FFF   16KB ROM Bank 01..NN (in cartridge, switchable bank number)     // PSRAM 000000-7FFFFF
//   8000-9FFF   8KB Video RAM (VRAM) (switchable bank 0-1 in CGB Mode)          // BRAM 8KB
//   A000-BFFF   8KB External RAM     (in cartridge, switchable bank, if any)    // PSRAM E00000-EFFFFF 512KB
//   C000-CFFF   4KB Work RAM Bank 0 (WRAM)                                      // PSRAM 80C000-80CFFF 4KB
//   D000-DFFF   4KB Work RAM Bank 1 (WRAM)                                      // PSRAM 80D000-80DFFF 4KB
//   E000-FDFF   Same as C000-DDFF (ECHO)    (typically not used)                // Mirror
//   FE00-FE9F   Sprite Attribute Table (OAM)                                    // BRAM
//   FEA0-FEFF   Not Usable
//   FF00-FF7F   I/O Ports                                                       // Reg
//   FF80-FFFE   High RAM (HRAM)                                                 // BRAM
//   FFFF        Interrupt Enable Register                                       // Reg
// 
// SNES
//   000000-07FFFF   SGB SNES ROM (512KB)                                        // 512KB RAM
// 
// MCU
//   000000-7FFFFF   PSRAM
//   800000-87FFFF   SGB
//     800000-8000FF   BOOT ROM
//     800100-807FFF   <unmapped> see 000000-7FFFFF
//     808000-809FFF   VRAM
//     80A000-80BFFF   <unmapped> see E00000-EFFFFF
//     80C000-80DFFF   WRAM
//     80FE00-80FFFF   OAM, IO, etc
//     810000-810FFF   Debug (read only)
//   880000-8FFFFF   RAM
//   900000-FFFFFF   PSRAM

wire [15:0]  CPU_SYS_ADDR;
wire [1:0]   CPU_PPU_PIXEL;
wire [1:0]   CPU_P1O;
wire [3:0]   CPU_P1I;

wire         ICD2_CLK_CPU_EDGE;

wire         REG_REQ;
wire [7:0]   REG_ADDR;
wire [7:0]   REG_DATA;
reg  [7:0]   MBC_REG_DATA;

wire [7:0]   DBG_DBG_DATA_OUT;
wire [7:0]   DBG_MBC_DATA_OUT;
wire         ICD2_CPU_RST;
assign       CPU_RST = ICD2_CPU_RST;

wire         MBC_BUS_RDY;
wire [7:0]   MBC_BUS_RDDATA;

parameter CONFIG_REGISTERS = 8;
reg [7:0] config_r[CONFIG_REGISTERS-1:0]; initial for (i = 0; i < CONFIG_REGISTERS; i = i + 1) config_r[i] = 8'h00;

assign       APU_CLK_EDGE = ICD2_CLK_CPU_EDGE;

//-------------------------------------------------------------------
// SGB2-CPU
//-------------------------------------------------------------------
sgb_cpu cpu(
  .RST(RST),
  .CPU_RST(ICD2_CPU_RST),
  .CLK(CLK),
  .CLK_CPU_EDGE(ICD2_CLK_CPU_EDGE),

  .SYS_RDY(MBC_BUS_RDY),
  .SYS_REQ(CPU_SYS_REQ),
  .SYS_WR(CPU_SYS_WR),
  .SYS_ADDR(CPU_SYS_ADDR),
  .SYS_RDDATA(MBC_BUS_RDDATA),
  .SYS_WRDATA(ROM_BUS_WRDATA),

  .BOOTROM_ACTIVE(CPU_BOOTROM_ACTIVE),
  .FREE_SLOT(CPU_FREE_SLOT),
  
  .PPU_DOT_EDGE(CPU_PPU_DOT_EDGE),
  .PPU_PIXEL_VALID(CPU_PPU_PIXEL_VALID),
  .PPU_PIXEL(CPU_PPU_PIXEL),
  .PPU_VSYNC_EDGE(CPU_PPU_VSYNC_EDGE),
  .PPU_HSYNC_EDGE(CPU_PPU_HSYNC_EDGE),
  
  .APU_DAT(APU_DAT),
  
  .P1O(CPU_P1O),
  .P1I(CPU_P1I),

  .HLT_REQ(HLT_REQ),
  .HLT_RSP(HLT_RSP),
  .IDL_ICD(IDL_ICD),
  
  .REG_REQ(REG_REQ),
  .REG_ADDR(REG_ADDR),
  .REG_DATA(REG_DATA),
  .MBC_REG_DATA(MBC_REG_DATA),
  
  .MCU_RRQ(MCU_RRQ),
  .MCU_WRQ(MCU_WRQ),
  .MCU_ADDR(MCU_ADDR),
  .MCU_DATA_IN(MCU_DATA_IN),
  .MCU_RSP(MCU_RSP),
  .MCU_DATA_OUT(MCU_DATA_OUT),

  .DBG_ADDR(DBG_ADDR),
  .DBG_ICD2_DATA_IN(DBG_ICD2_DATA_OUT),
  .DBG_MBC_DATA_IN(DBG_MBC_DATA_OUT),
  .DBG_CHEAT_DATA_IN(DBG_CHEAT_DATA_IN),
  .DBG_MAIN_DATA_IN(DBG_MAIN_DATA_IN),
  
  .DBG_CONFIG({config_r[7],config_r[6],config_r[5],config_r[4],config_r[3],config_r[2],config_r[1],config_r[0]}),
  .DBG_BRK(CPU_DBG_BRK)
);

//-------------------------------------------------------------------
// ICD2
//-------------------------------------------------------------------

sgb_icd2 icd2(
  .RST(RST),
  .CPU_RST(ICD2_CPU_RST),
  .CLK(CLK),
  .CLK_CPU_EDGE(ICD2_CLK_CPU_EDGE),

  .SNES_RD_start(SNES_RD_start),
  .SNES_WR_end(SNES_WR_end),
  .SNES_ADDR(SNES_ADDR),
  .DATA_IN(DATA_IN),
  .DATA_OUT(DATA_OUT),
  
  .PPU_DOT_EDGE(CPU_PPU_DOT_EDGE),
  .PPU_PIXEL_VALID(CPU_PPU_PIXEL_VALID),
  .PPU_PIXEL(CPU_PPU_PIXEL),
  .PPU_VSYNC_EDGE(CPU_PPU_VSYNC_EDGE),
  .PPU_HSYNC_EDGE(CPU_PPU_HSYNC_EDGE),
  
  .P1I(CPU_P1O),
  .P1O(CPU_P1I),

  .IDL(IDL_ICD),
  
  .DBG_ADDR(DBG_ADDR),
  .DBG_DATA_OUT(DBG_ICD2_DATA_OUT)
);

//-------------------------------------------------------------------
// RTC
//-------------------------------------------------------------------

`define RTC_CTL_DAY   0
`define RTC_CTL_HALT  6
`define RTC_CTL_CARRY 7

reg  [5:0]  rtc_sec_r = 0; // 08
reg  [5:0]  rtc_min_r = 0; // 09
reg  [4:0]  rtc_hrs_r = 0; // 0A
reg  [7:0]  rtc_day_r = 0; // 0B
reg  [7:0]  rtc_ctl_r = 0; // 0C

reg  [31:0] rtc_tick_r = 0;

reg         rtc_write_r;
reg  [7:0]  rtc_write_address_r;
reg  [7:0]  rtc_write_data_r;
reg         rtc_written_r = 0;

reg         dbg_rtc_write_r = 0;

assign rtc_tick_ast = &rtc_tick_r[26:26] & &rtc_tick_r[24:24] & &rtc_tick_r[16:15] & &rtc_tick_r[13:10] & &rtc_tick_r[7:0]; // 84000000-1
assign rtc_sec_ast  = &rtc_sec_r[5:3] & &rtc_sec_r[1:0]; // 60-1
assign rtc_min_ast  = &rtc_min_r[5:3] & &rtc_min_r[1:0]; // 60-1
assign rtc_hrs_ast  =  rtc_min_r[4:4] & &rtc_min_r[2:0]; // 23-1
assign rtc_day_ast  = &{rtc_ctl_r[`RTC_CTL_DAY],rtc_day_r}; // 511

wire        MBC_RTC_write;
wire [7:0]  MBC_RTC_address;
wire [7:0]  MBC_RTC_data;

assign RTC_DAT = {rtc_written_r, rtc_tick_r[30:24],rtc_tick_r[23:16],rtc_ctl_r,rtc_day_r,3'h0,rtc_hrs_r,2'h0,rtc_min_r,2'h0,rtc_sec_r};

always @(posedge CLK) begin
  rtc_tick_r <= (rtc_tick_ast | rtc_ctl_r[`RTC_CTL_HALT]) ? 0 : rtc_tick_r + 1;

  if (rtc_tick_ast)                                                         rtc_sec_r <= rtc_sec_ast ? 0 : rtc_sec_r + 1;
  if (rtc_tick_ast & rtc_sec_ast)                                           rtc_min_r <= rtc_min_ast ? 0 : rtc_min_r + 1;
  if (rtc_tick_ast & rtc_sec_ast & rtc_min_ast)                             rtc_hrs_r <= rtc_hrs_ast ? 0 : rtc_hrs_r + 1;
  if (rtc_tick_ast & rtc_sec_ast & rtc_min_ast & rtc_hrs_ast)               {rtc_ctl_r[`RTC_CTL_DAY],rtc_day_r} <= rtc_day_ast ? 0 : {rtc_ctl_r[`RTC_CTL_DAY],rtc_day_r} + 1;
  if (rtc_tick_ast & rtc_sec_ast & rtc_min_ast & rtc_hrs_ast & rtc_day_ast) rtc_ctl_r[`RTC_CTL_CARRY] <= 1;  
  
  if (ICD2_CPU_RST) begin
    rtc_write_r <= 0;
  end
  else begin
    rtc_write_r <= 0;
    if (MBC_RTC_write) begin
      rtc_write_r         <= 1;
      rtc_write_address_r <= MBC_RTC_address;
      rtc_write_data_r    <= MBC_RTC_data;

      rtc_written_r       <= 1;
    end
    else begin
      if (RTC_DAT_RD & ~rtc_ctl_r[`RTC_CTL_HALT]) rtc_written_r <= 0;
    end
  end
  
  if (rtc_write_r) begin
    case (rtc_write_address_r)
      8'h08: rtc_sec_r[5:0] <= rtc_write_data_r[5:0];
      8'h09: rtc_min_r[5:0] <= rtc_write_data_r[5:0];
      8'h0A: rtc_hrs_r[4:0] <= rtc_write_data_r[4:0];
      8'h0B: rtc_day_r[7:0] <= rtc_write_data_r[7:0];
      8'h0C: rtc_ctl_r[7:0] <= rtc_write_data_r[7:0];
    endcase
  end

  // TODO: decide if we should save RTC state.  There are races with transitions during save so we would need to flop a consistent value
  // or halt the counter on save/load.  Probably better to halt the counter when HLT_RSP is asserted to make life easy.  But we will lose
  // a small amount of time that way even on a save.
  
  if (RTC_DAT_WE) begin
    dbg_rtc_write_r <= 1;
    {rtc_tick_r[31:24],rtc_tick_r[23:16],rtc_ctl_r,rtc_day_r,/*3'h0,*/rtc_hrs_r,/*2'h0,*/rtc_min_r,/*2'h0,*/rtc_sec_r} <= {RTC_DAT_IN[55:24],RTC_DAT_IN[20:16],RTC_DAT_IN[13:8],RTC_DAT_IN[5:0]};
  end
end

//-------------------------------------------------------------------
// MAP
//-------------------------------------------------------------------

`define MAPPER_ID  2:0
`define MAPPER_EX  3:3

reg  [8:0]  mbc_rom_bank_r;
reg  [8:0]  mbc_rom0_bank_r;
reg  [6:0]  mbc_ram_bank_r;

reg         mbc_reg_ram_enabled_r;
reg         mbc_reg_rom_bank_upper_r;
reg  [7:0]  mbc_reg_rom_bank_r;
reg  [7:0]  mbc_reg_bank_r;
reg         mbc_reg_mode_r;

reg         mbc_rtc_write_r;
reg  [7:0]  mbc_rtc_sec_r = 0;
reg  [7:0]  mbc_rtc_min_r = 0;
reg  [7:0]  mbc_rtc_hrs_r = 0;
reg  [7:0]  mbc_rtc_day_r = 0;
reg  [7:0]  mbc_rtc_ctl_r = 0;

`define MBC_DELAY 2 // minimum 2
reg  [`MBC_DELAY-1:0]  mbc_req_r;
reg                    mbc_req_rtc_r;
reg                    mbc_req_srm_mbc2_r;
reg  [7:0]             mbc_data_r;

reg  [7:0]  dbg_data_r;

// provide state for saves
always @(*) begin
  case (REG_ADDR)
    8'h70:   MBC_REG_DATA = mbc_reg_ram_enabled_r;
    8'h71:   MBC_REG_DATA = mbc_reg_rom_bank_upper_r;
    8'h72:   MBC_REG_DATA = mbc_reg_rom_bank_r;
    8'h73:   MBC_REG_DATA = mbc_reg_bank_r;
    8'h74:   MBC_REG_DATA = mbc_reg_mode_r;
    default: MBC_REG_DATA = 0;
  endcase
end

// handle expansion bit
wire        mbc_map_rtc = MAPPER[`MAPPER_EX] && MAPPER[`MAPPER_ID] == 3; // MBC3 supports RTC
wire        mbc_map_mlt = MAPPER[`MAPPER_EX] && MAPPER[`MAPPER_ID] == 1; // MBC1 supports (M)ulticart (MBC1M)

// MAP has logic to translate the CPU address
// to ROM (bootROM), SaveRAM, and WRAM addresses.  It represents
// the cartridge addressing logic, some basic CPU address
// logic to handle boot ROM, as well as SD2SNES specific addressing.

// NOTE: we can ignore checking address for 8000-9FFF because they are never sent here
// These are only valid on the first cycle of the request.
assign mbc_bus_mbc = CPU_SYS_REQ & CPU_SYS_WR & ~CPU_SYS_ADDR[15];
assign mbc_bus_dis = CPU_SYS_REQ & CPU_SYS_WR &  CPU_SYS_ADDR[15] & ~CPU_SYS_ADDR[14] & ~mbc_reg_ram_enabled_r;
assign mbc_bus_rtc = CPU_SYS_REQ &               CPU_SYS_ADDR[15] & ~CPU_SYS_ADDR[14] &  mbc_reg_ram_enabled_r & |mbc_reg_bank_r[7:3] & mbc_map_rtc;
assign mbc_bus_req = mbc_bus_mbc | mbc_bus_rtc | mbc_bus_dis;
                     
assign ROM_BUS_RRQ = CPU_SYS_REQ & ~CPU_SYS_WR & ~mbc_bus_req;
assign ROM_BUS_WRQ = CPU_SYS_REQ &  CPU_SYS_WR & ~mbc_bus_req;
assign ROM_BUS_WORD = 0; // SGB has 8b data bus

wire   BOOTROM = CPU_BOOTROM_ACTIVE & ~|CPU_SYS_ADDR[13:8];

assign ROM_BUS_ADDR = ( (~|CPU_SYS_ADDR[15:14]) ? ({BOOTROM,(mbc_rom0_bank_r[8:0] & ROM_MASK[22:14]),(CPU_SYS_ADDR[13:0] & ROM_MASK[13:0])})   // ROM     0000-3FFF -> 000000-003FFF,800000-8000FF (cart+boot) - 16KB programmable MBC1 else fixed
                      : (~CPU_SYS_ADDR[15])     ? ({1'h0,   (mbc_rom_bank_r[8:0]  & ROM_MASK[22:14]),(CPU_SYS_ADDR[13:0] & ROM_MASK[13:0])})   // ROM     4000-7FFF -> 004000-7FFFFF (cart) - 16KB programmable
                                                                                                                                               // VRAM    8000-9FFF -> NA - 8 KB (BRAM)
                      : (~CPU_SYS_ADDR[14])     ? {4'hE,(mbc_ram_bank_r[6:0] & SAVERAM_MASK[19:13]),(CPU_SYS_ADDR[12:0] & SAVERAM_MASK[12:0])} // SaveRAM A000-BFFF -> E00000-EFFFFF - 8KB programmable
                      :                           {8'h80,3'b110,              CPU_SYS_ADDR[12:0]}                                              // WRAM    C000-DFFF -> 80C000-80DFFF 4+4=8 KB fixed
                      );                                                                                                                       //         E000-FDFF -> 80C000-80DFFF (mirror of C000-DDFF)
                                                                                                                                               // OAM     FE00-FE9F -> NA - 160B (BRAM)
                                                                                                                                               // -       FEA0-FEFF -> NA
                                                                                                                                               // REG     FF00-FF7F -> NA - 128B (REG)
                                                                                                                                               //              FFFF
                                                                                                                                               // HRAM    FF80-FFFE -> NA - 127B (BRAM)

assign DBG_MBC_DATA_OUT = dbg_data_r;

assign ROM_FREE_SLOT = CPU_FREE_SLOT;

assign MBC_BUS_RDY    = ~|mbc_req_r ? ROM_BUS_RDY                                                             : mbc_req_r[`MBC_DELAY-1];
assign MBC_BUS_RDDATA = ~|mbc_req_r ? {(mbc_req_srm_mbc2_r ? 4'hF : ROM_BUS_RDDATA[7:4]),ROM_BUS_RDDATA[3:0]} : mbc_data_r;

assign MBC_RTC_write = mbc_rtc_write_r;
assign MBC_RTC_address = mbc_reg_bank_r[7:0];
assign MBC_RTC_data = ROM_BUS_WRDATA;

always @(posedge CLK) begin
  if (RST) begin
    mbc_reg_ram_enabled_r <= 0;
    mbc_reg_rom_bank_upper_r <= 0;
    mbc_reg_rom_bank_r    <= 8'h01;
    mbc_reg_bank_r        <= 8'h00;
    mbc_reg_mode_r        <= 0;
  end
  else begin
    if (mbc_bus_mbc) begin
      if (MAPPER[`MAPPER_ID] == 2) begin
        if (CPU_SYS_ADDR[8]) mbc_reg_rom_bank_r[7:0] <= ROM_BUS_WRDATA[7:0]; else mbc_reg_ram_enabled_r <= (ROM_BUS_WRDATA[3:0] == 4'hA) ? 1 : 0;
      end
      else begin
        case (CPU_SYS_ADDR[14:13])
          0: mbc_reg_ram_enabled_r   <= (ROM_BUS_WRDATA[3:0] == 4'hA) ? 1 : 0;
          1: begin
            if (MAPPER[`MAPPER_ID] == 3) begin
              if (CPU_SYS_ADDR[12]) mbc_reg_rom_bank_upper_r <= ROM_BUS_WRDATA[0]; else mbc_reg_rom_bank_r[7:0] <= ROM_BUS_WRDATA[7:0];
            end
            else begin
              mbc_reg_rom_bank_upper_r <= 0;
              mbc_reg_rom_bank_r[7:0]  <= ROM_BUS_WRDATA[7:0];
            end
          end
          2: mbc_reg_bank_r[7:0]     <= ROM_BUS_WRDATA[7:0];
          3: begin
            mbc_reg_mode_r <= ROM_BUS_WRDATA[0];
            
            if (~mbc_reg_mode_r & ROM_BUS_WRDATA[0]) begin
              // Save RTC for MBC3
              mbc_rtc_sec_r <= {2'h0,rtc_sec_r};
              mbc_rtc_min_r <= {2'h0,rtc_min_r};
              mbc_rtc_hrs_r <= {3'h0,rtc_hrs_r};
              mbc_rtc_day_r <= rtc_day_r;
              mbc_rtc_ctl_r <= rtc_ctl_r;
            end
          end
        endcase
      end
    end
  end

  if (ICD2_CPU_RST) begin
    mbc_req_r <= 0;
    mbc_req_srm_mbc2_r <= 0;

    mbc_rtc_write_r <= 0;
  end
  else begin
    // MBC memory requests
    mbc_req_r <= {mbc_req_r[`MBC_DELAY-2:0],mbc_bus_req};
    if (CPU_SYS_REQ) mbc_req_rtc_r      <= mbc_bus_rtc;
    if (CPU_SYS_REQ) mbc_req_srm_mbc2_r <= MAPPER[`MAPPER_ID] == 2 && (CPU_SYS_ADDR[15] & ~CPU_SYS_ADDR[14]);
    
    if (mbc_req_r[0]) begin
      if (mbc_req_rtc_r) begin
        case (mbc_reg_bank_r)
          8'h08:   mbc_data_r <= mbc_rtc_sec_r;
          8'h09:   mbc_data_r <= mbc_rtc_min_r;
          8'h0A:   mbc_data_r <= mbc_rtc_hrs_r;
          8'h0B:   mbc_data_r <= mbc_rtc_day_r;
          8'h0C:   mbc_data_r <= {mbc_rtc_ctl_r[7:6],5'h1F,mbc_rtc_ctl_r[0]};
          
          default: mbc_data_r <= 8'hFF;
        endcase
      end
      else begin
        mbc_data_r <= 8'hFF;
      end
    end
  
    if (mbc_bus_rtc & CPU_SYS_WR) begin
      mbc_rtc_write_r <= 1;
    end
    else if (rtc_write_r) begin
      mbc_rtc_write_r <= 0;
    end
  end
  
  mbc_ram_bank_r[6:0] <= ( MAPPER[`MAPPER_ID] == 1 ? {5'h00,((mbc_reg_mode_r & ~mbc_map_mlt) ? mbc_reg_bank_r[1:0] : 2'h0)}
                         : MAPPER[`MAPPER_ID] == 2 ? 7'h00
                         : MAPPER[`MAPPER_ID] == 3 ? {3'h0,mbc_reg_bank_r[3:0]}
                         : MAPPER[`MAPPER_ID] == 5 ? {3'h0,mbc_reg_bank_r[3:0]}
                         :                           7'h00
                         );
    
  mbc_rom_bank_r[8:0] <= ( MAPPER[`MAPPER_ID] == 1 ? (mbc_map_mlt ? {3'h0,mbc_reg_bank_r[1],({mbc_reg_bank_r[0],mbc_reg_rom_bank_r[3:0]} | ~|{mbc_reg_bank_r[0],mbc_reg_rom_bank_r[3:0]})}
                                                                  : {2'h0,mbc_reg_bank_r[1:0],(mbc_reg_rom_bank_r[4:0] | ~|mbc_reg_rom_bank_r[4:0])})
                         : MAPPER[`MAPPER_ID] == 2 ? {5'h00,mbc_reg_rom_bank_r[3:0] | ~|mbc_reg_rom_bank_r[3:0]}
                         : MAPPER[`MAPPER_ID] == 3 ? {1'b0,mbc_reg_rom_bank_r[7:0] | ~|mbc_reg_rom_bank_r[7:0]}
                         : MAPPER[`MAPPER_ID] == 5 ? {mbc_reg_rom_bank_upper_r,mbc_reg_rom_bank_r[7:0]}
                         :                           9'h001
                         );
                         
  mbc_rom0_bank_r[8:0] <= ( MAPPER[`MAPPER_ID] == 1 ? {2'h0,(mbc_reg_mode_r ? (mbc_map_mlt ? {1'b0,mbc_reg_bank_r[1:0]} : {mbc_reg_bank_r[1:0],1'b0}) : 3'h0),4'h00}
                          :                           9'h000
                          );
                         
  // write in state for loads
  if (REG_REQ) begin
    case (REG_ADDR)
      8'h70: mbc_reg_ram_enabled_r    <= REG_DATA;
      8'h71: mbc_reg_rom_bank_upper_r <= REG_DATA;
      8'h72: mbc_reg_rom_bank_r       <= REG_DATA;
      8'h73: mbc_reg_bank_r           <= REG_DATA;
      8'h74: mbc_reg_mode_r           <= REG_DATA;
    endcase
  end
                         
  casez(DBG_ADDR[3:0])
    4'h0:    dbg_data_r <= mbc_reg_ram_enabled_r;
    4'h1:    dbg_data_r <= mbc_reg_mode_r;
    4'h2:    dbg_data_r <= mbc_reg_rom_bank_r;
    4'h3:    dbg_data_r <= mbc_reg_bank_r;
    4'h4:    dbg_data_r <= mbc_rom_bank_r;
    4'h5:    dbg_data_r <= mbc_ram_bank_r;
    4'h6:    dbg_data_r <= CPU_BOOTROM_ACTIVE;
    4'h7:    dbg_data_r <= dbg_rtc_write_r;

    4'h8:    dbg_data_r <= rtc_sec_r;
    4'h9:    dbg_data_r <= rtc_min_r;
    4'hA:    dbg_data_r <= rtc_hrs_r;
    4'hB:    dbg_data_r <= rtc_day_r;
    4'hC:    dbg_data_r <= rtc_ctl_r;

    4'hD:    dbg_data_r <= MAPPER;
    4'hE:    dbg_data_r <= mbc_req_r;
    4'hF:    dbg_data_r <= mbc_data_r;

    default:  dbg_data_r <= 0;
  endcase
end

`ifdef SGB_DEBUG
//-------------------------------------------------------------------
// CONFIG
//-------------------------------------------------------------------

// C0 Control
// 0 - Go (1)
// 1 - MatchFullInst

// C1 StepControl
// [7:0] StepCount

// C2 BreakpointControl
// 0 - BreakOnInstRdByteWatch
// 1 - BreakOnDataRdByteWatch
// 2 - BreakOnDataWrByteWatch
// 3 - BreakOnInstRdAddrWatch
// 4 - BreakOnDataRdAddrWatch
// 5 - BreakOnDataWrAddrWatch
// 6 - BreakOnStop
// 7 - BreakOnError

// C3 ???

// C4 DataWatch
// [7:0] DataWatch

// C5-C7 AddrWatch (little endian)
// [23:0] AddrWatch
always @(posedge CLK) begin
  if (reg_we_in && (reg_group_in == 8'h03)) begin
    if (reg_index_in < CONFIG_REGISTERS) config_r[reg_index_in] <= (config_r[reg_index_in] & reg_invmask_in) | (reg_value_in & ~reg_invmask_in);
  end
  else begin
    config_r[0][0] <= config_r[0][0] | CPU_DBG_BRK;
  end
end

assign config_data_out = config_r[reg_read_in];
`endif

endmodule
