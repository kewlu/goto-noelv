library ieee;
use ieee.std_logic_1164.all;

library grlib, techmap;
use grlib.amba.all;
use grlib.devices.all;
use grlib.stdlib.all;
use grlib.config.all;
use grlib.config_types.all;
use techmap.gencomp.all;
use techmap.allclkgen.all;

library gaisler;
use gaisler.noelv.all;
use gaisler.uart.all;
use gaisler.misc.all;
use gaisler.spi.all;
use gaisler.net.all;
use gaisler.jtag.all;
use gaisler.i2c.all;
use gaisler.subsys.all;
use gaisler.axi.all;
use gaisler.plic.all;
use gaisler.riscv.all;
use gaisler.l2cache.all;
use gaisler.noelv.all;
-- pragma translate_off
use gaisler.sim.all;

library unisim;
use unisim.all;
-- pragma translate_on


use work.config.all;

entity top is
	generic(
    fabtech             : integer := CFG_FABTECH;
    memtech             : integer := CFG_MEMTECH;
    padtech             : integer := CFG_PADTECH;
    clktech             : integer := CFG_CLKTECH;
    disas               : integer := CFG_DISAS;
    migmodel            : boolean := false;
    autonegotiation     : integer := 1
				
	);
	port(
		reset : in std_ulogic;
		clk50p : in std_ulogic;
		clk50n : in std_ulogic;		
	);
end;

architecture rtl of top is

  -----------------------------------------------------
  -- Constants ----------------------------------------
  -----------------------------------------------------

  constant maxahbm      : integer := 16;
  constant maxahbs      : integer := 16;

  constant OEPOL        : integer := padoen_polarity(padtech);

  constant BOARD_FREQ   : integer := 300000; -- input frequency in KHz
  constant CPU_FREQ     : integer := BOARD_FREQ * CFG_CLKMUL / CFG_CLKDIV; -- cpu frequency in KHz

  constant USE_MIG_INTERFACE_MODEL      : boolean := migmodel;

  constant ramfile      : string := "ram.srec"; -- ram contents
  
  -----------------------------------------------------
  -- Signals ------------------------------------------
  -----------------------------------------------------

  -- Misc
  signal vcc            : std_ulogic;
  signal gnd            : std_ulogic;
  signal stati          : ahbstat_in_type;
  signal dsu_sel        : std_ulogic;

  -- Memory
  signal mem_aximi      : axi_somi_type;
  signal mem_aximo      : axi_mosi_type;
  signal axi3_aximo     : axi3_mosi_type;
  
  signal migrstn        : std_ulogic;
  signal calib_done     : std_ulogic;

  -- Memory AHB Signals
  signal mem_ahbmi      : ahb_mst_in_type;
  signal mem_ahbmo      : ahb_mst_out_type;
  signal mem_ahbsi      : ahb_slv_in_type;
  signal mem_ahbso      : ahb_slv_out_type;
  
  -- APB
  signal apbi           : apb_slv_in_vector;
  signal apbo           : apb_slv_out_vector := (others => apb_none);

  -- AHB
  signal ahbsi          : ahb_slv_in_type;
  signal ahbso          : ahb_slv_out_vector := (others => ahbs_none);
  signal ahbmi          : ahb_mst_in_type;
  signal ahbmo          : ahb_mst_out_vector := (others => ahbm_none);

  -- NOELV
  signal ext_irqi       : std_logic_vector(15 downto 0);
  signal cpurstn        : std_ulogic;

  -- Clocks and Reset
  signal clkm           : std_ulogic := '0';
  signal rstn           : std_ulogic;
  signal rstraw         : std_ulogic;
  signal clk_300        : std_ulogic;
  signal cgi            : clkgen_in_type;
  signal cgo            : clkgen_out_type;

  signal clklock        : std_ulogic;
  signal lock           : std_ulogic;
  signal lclk           : std_ulogic;
  signal rst            : std_ulogic;
  signal clkref         : std_ulogic;

  -- Ethernet
  signal gmiii          : eth_in_type;
  signal gmiio          : eth_out_type;
  signal sgmiii         : eth_sgmii_in_type; 
  signal sgmiio         : eth_sgmii_out_type;
  
  signal sgmiirst       : std_ulogic;
  signal ethernet_phy_int : std_ulogic;

  signal rxd1           : std_ulogic;
  signal txd1           : std_ulogic;

  signal ethi           : eth_in_type;
  signal etho           : eth_out_type;
  signal egtx_clk       : std_ulogic;
  signal negtx_clk      : std_ulogic;

  signal clkout0o       : std_ulogic;
  signal clkout1o       : std_ulogic;
  signal clkout2o       : std_ulogic;

  signal e1_debug_rx    : std_logic_vector(63 downto 0);
  signal e1_debug_tx    : std_logic_vector(63 downto 0);
  signal e1_debug_gtx   : std_logic_vector(63 downto 0);

  -- I2C
  signal i2ci           : i2c_in_type;
  signal i2co           : i2c_out_type;

  -- APB UART
  signal u1i            : uart_in_type;
  signal u1o            : uart_out_type;

  -- AHB UART
  signal dui            : uart_in_type;
  signal duo            : uart_out_type;

  signal dsurx_int      : std_ulogic; 
  signal dsutx_int      : std_ulogic; 
  signal dsuctsn_int    : std_ulogic;
  signal dsurtsn_int    : std_ulogic;

  -- Timers
  signal gpti           : gptimer_in_type;
  signal gpto           : gptimer_out_type;

  -- GPIOs
  signal gpioi          : gpio_in_type;
  signal gpioo          : gpio_out_type;

  -- JTAG
  signal tck            : std_ulogic;
  signal tckn           : std_ulogic;
  signal tms            : std_ulogic;
  signal tdi            : std_ulogic;
  signal tdo            : std_ulogic;

  -- SPI
  signal spii           : spi_in_type;
  signal spio           : spi_out_type;
  signal slvsel         : std_logic_vector(CFG_SPICTRL_SLVS-1 downto 0);

  -- Irq Bus
  signal irqi           : nv_irq_in_vector(0 to CFG_NCPU-1);
  signal eip            : std_logic_vector(CFG_NCPU*4-1 downto 0);

  -- Debug Bus
  signal dbgi           : nv_debug_in_vector(0 to CFG_NCPU-1);
  signal dbgo           : nv_debug_out_vector(0 to CFG_NCPU-1);
  signal dsui           : nv_dm_in_type;
  signal dsuo           : nv_dm_out_type;

  -- Real Time Clock
  signal rtc            : std_ulogic := '0';

  -- FPU Unit
  signal fpi            : fpu5_in_vector_type;
  signal fpo            : fpu5_out_vector_type;

  -- Trace buffer
  signal trace_ahbsiv     : ahb_slv_in_vector_type(0 to 1);
  signal trace_ahbmiv     : ahb_mst_in_vector_type(0 to 1);

  constant ncpu     : integer := CFG_NCPU;
  constant nextslv  : integer := 3
-- pragma translate_off
  + 1
-- pragma translate_on
  ;
  constant ndbgmst  : integer := 3
  ;
  signal ldsuen     : std_logic;
  signal ldsubreak  : std_logic;
  signal lcpu0errn  : std_logic;
  signal dbgmi      : ahb_mst_in_vector_type(ndbgmst-1 downto 0);
  signal dbgmo      : ahb_mst_out_vector_type(ndbgmst-1 downto 0);
  
  ----------------------------------------------------------------------
  ---  NOEL-V SUBSYSTEM ------------------------------------------------
  ----------------------------------------------------------------------
  noelv0 : noelvsys
  	generic map(
      fabtech   => fabtech,
      memtech   => memtech,
      ncpu      => ncpu,
      nextmst   => 1,--2,
      nextslv   => nextslv,
      nextapb   => 6,
      ndbgmst   => ndbgmst,
      cached    => 0,
      wbmask    => 16#00FF#,
      busw      => 128,
      cmemconf  => 4,
      fpuconf   => 0,
      disas     => 1,
      ahbtrace  => 0,
      cfg       => 1,
      devid     => 0,
      version   => 0,
      revision  => 7,
      nodbus    => CFG_NODBGBUS  		
  	)
  	port map(
  	  clk       => clkm,
      rstn      => rstn,
      -- AHB bus interface for other masters (DMA units)
      ahbmi     => ahbmi,                     -- : out ahb_mst_in_type;
      ahbmo     => ahbmo(ncpu downto ncpu),   -- : in  ahb_mst_out_vector_type(ncpu+nextmst-1 downto ncpu);
      -- AHB bus interface for slaves (memory controllers, etc)
      ahbsi     => ahbsi,                     -- : out ahb_slv_in_type;
      ahbso     => ahbso(nextslv-1 downto 0), -- : in  ahb_slv_out_vector_type(nextslv-1 downto 0);
      -- AHB master interface for debug links
      dbgmi     => dbgmi,                     -- : out ahb_mst_in_vector_type(ndbgmst-1 downto 0);
      dbgmo     => dbgmo,                     -- : in  ahb_mst_out_vector_type(ndbgmst-1 downto 0);
      -- APB interface for external APB slaves
      apbi      => apbi,                      -- : out apb_slv_in_type;
      apbo      => apbo,                      -- : in  apb_slv_out_vector;
      -- Bootstrap signals
      dsuen     => ldsuen,
      dsubreak  => ldsubreak,
      cpu0errn  => lcpu0errn,
      -- UART connection
      uarti     => u1i,
      uarto     => u1o
  	);
  	
  -----------------------------------------------------------------------
  ---  AHB ROM ----------------------------------------------------------
  -----------------------------------------------------------------------

  brom : entity work.ahbrom
    generic map (
      hindex  => 1,
      haddr   => 16#000#,
      pipe    => 0)
    port map (
      rst     => rstn,
      clk     => clkm,
      ahbsi   => ahbsi,
      ahbso   => ahbso(1));
  
  	
  -----------------------------------------------------------------------------
  -- JTAG debug link ----------------------------------------------------------
  -----------------------------------------------------------------------------
  
  ahbjtaggen0 : if CFG_AHB_JTAG = 1 generate
    ahbjtag0 : ahbjtag
      generic map(tech => fabtech, hindex => 1)
      port map(rstn, clkm, tck, tms, tdi, tdo, dbgmi(1), dbgmo(1),
               open, open, open, open, open, open, open, gnd(0));
  end generate;

  nojtag : if CFG_AHB_JTAG = 0 generate
    dbgmo(1) <= ahbm_none;
end generate;

----------------------------------------------------------------------
---  Reset and Clock generation  -------------------------------------
----------------------------------------------------------------------

  vcc <= (others => '1'); gnd <= (others => '0');
  cgi.pllctrl <= "00"; cgi.pllrst <= rstraw;

reset_pad : inpad generic map (tech => padtech, level => cmos, voltage => x18v) port map (reset, rst);
	
  rst0 : rstgen         -- reset generator
  generic map (acthigh => 1, syncin => 0)
  port map (rst, clkm, lock, rstn, rstraw);
  lock <= (calib_done and clk125_lock) when CFG_MIG_7SERIES = 1 else cgo.clklock;
  
  rst1 : rstgen         -- reset generator
  generic map (acthigh => 1)
  port map (rst, clkm, lock, migrstn, open);

  rst2 : rstgen         -- reset generator (USB)
  generic map (acthigh => 1)
  port map (rst, uclk, vcc(0), urstn, open);
  
 
   clk_gen : if (CFG_MIG_7SERIES = 0) generate
     clk_pad_ds : clkpad_ds generic map (tech => padtech, level => sstl, voltage => x15v) port map (clk50p, clk50n, lclk);
     clkgen0 : clkgen        -- clock generator
       generic map (clktech, CFG_CLKMUL, CFG_CLKDIV, CFG_MCTRL_SDEN,
      CFG_CLK_NOFB, 0, 0, 0, BOARD_FREQ)
       port map (lclk, lclk, clkm, open, open, open, open, cgi, cgo, open, open, open);
   end generate;
   
    
end rtl;

