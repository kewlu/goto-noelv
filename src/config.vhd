library techmap;
use techmap.gencomp.all;
package config is
-- Technology and synthesis options
  constant CFG_FABTECH : integer := virtex5;
  constant CFG_MEMTECH : integer := virtex5;
  constant CFG_PADTECH : integer := virtex5;
  constant CFG_TRANSTECH : integer := TT_XGTP0;
  constant CFG_NOASYNC : integer := 0;
  constant CFG_SCAN : integer := 0;
-- Clock generator
  constant CFG_CLKTECH : integer := virtex5;
  constant CFG_CLKMUL : integer := (7);
  constant CFG_CLKDIV : integer := (5);
  constant CFG_OCLKDIV : integer := 1;
  constant CFG_OCLKBDIV : integer := 0;
  constant CFG_OCLKCDIV : integer := 0;
  constant CFG_PCIDLL : integer := 0;
  constant CFG_PCISYSCLK: integer := 0;
  constant CFG_CLK_NOFB : integer := 0;
-- NOEL-V processor core
  constant CFG_NOELV : integer := 1;
  constant CFG_NCPU : integer := (1);
  constant CFG_CFG : integer := (0);
  constant CFG_NODBUS : integer := 1;
  constant CFG_DISAS : integer := 0;
-- AMBA settings
  constant CFG_DEFMST : integer := (0);
  constant CFG_RROBIN : integer := 1;
  constant CFG_SPLIT : integer := 1;
  constant CFG_FPNPEN : integer := 1;
  constant CFG_AHBIO : integer := 16#FFF#;
  constant CFG_APBADDR : integer := 16#800#;
  constant CFG_AHB_MON : integer := 0;
  constant CFG_AHB_MONERR : integer := 0;
  constant CFG_AHB_MONWAR : integer := 0;
  constant CFG_AHB_DTRACE : integer := 0;
-- DSU UART
  constant CFG_AHB_UART : integer := 1;
-- JTAG based DSU interface
  constant CFG_AHB_JTAG : integer := 1;
-- FTMCTRL memory controller
  constant CFG_MCTRLFT : integer := 0;
  constant CFG_MCTRLFT_RAM8BIT : integer := 0;
  constant CFG_MCTRLFT_RAM16BIT : integer := 0;
  constant CFG_MCTRLFT_5CS : integer := 0;
  constant CFG_MCTRLFT_SDEN : integer := 0;
  constant CFG_MCTRLFT_SEPBUS : integer := 0;
  constant CFG_MCTRLFT_INVCLK : integer := 0;
  constant CFG_MCTRLFT_SD64 : integer := 0;
  constant CFG_MCTRLFT_EDAC : integer := 0 + 0 + 0;
  constant CFG_MCTRLFT_PAGE : integer := 0 + 0;
  constant CFG_MCTRLFT_ROMASEL : integer := 0;
  constant CFG_MCTRLFT_WFB : integer := 0;
  constant CFG_MCTRLFT_NET : integer := 0;
-- AHB status register
  constant CFG_AHBSTAT : integer := 1;
  constant CFG_AHBSTATN : integer := (1);
-- AHB RAM
  constant CFG_AHBRAMEN : integer := 0;
  constant CFG_AHBRSZ : integer := 4;
  constant CFG_AHBRADDR : integer := 16#A00#;
  constant CFG_AHBRPIPE : integer := 0;
-- GRLIB debugging
  constant CFG_DUART : integer := 0;
end;
