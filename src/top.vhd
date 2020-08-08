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
use gaisler.grusb.all;
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
		resetn      : in  std_logic;
		pllref      : in std_logic;
		clk : in std_ulogic
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
  signal lresetn 		: std_ulogic;
  signal clkm, rstn, rstraw : std_logic;

  -- Memory AHB Signals
  signal mem_ahbmi      : ahb_mst_in_type;
  signal mem_ahbmo      : ahb_mst_out_type;
  signal mem_ahbsi      : ahb_slv_in_type;
  signal mem_ahbso      : ahb_slv_out_type;
  -- AHB
  signal ahbsi          : ahb_slv_in_type;
  signal ahbso          : ahb_slv_out_vector := (others => ahbs_none);
  signal ahbmi          : ahb_mst_in_type;
  signal ahbmo          : ahb_mst_out_vector := (others => ahbm_none);
  
  signal usbi : grusb_in_vector(0 downto 0);
  signal usbo : grusb_out_vector(0 downto 0);

  -- NOELV
  signal ext_irqi       : std_logic_vector(15 downto 0);
  signal cpurstn        : std_ulogic;

  -- Clocks and Reset
  signal clk_300        : std_ulogic;
  signal cgi            : clkgen_in_type;
  signal cgo            : clkgen_out_type;

  signal clklock        : std_ulogic;
  signal lock           : std_ulogic;
  signal lclk           : std_ulogic;
  signal rst            : std_ulogic;
  signal clkref         : std_ulogic;

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
      nodbus    => CFG_NODBUS 		
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
      -- Bootstrap signals
      dsuen     => ldsuen,
      dsubreak  => ldsubreak,
      cpu0errn  => lcpu0errn,
      -- UART connection
      uarti     => ('0', '0', '0'),      uarto     => ('0', '0', (others => '0'), '0', '0', '0', '0', '0')
  	);
  	
  ----------------------------------------------------------------------
  ---  AHB RAM ----------------------------------------------------------
  -----------------------------------------------------------------------
  ocram : if CFG_AHBRAMEN = 1 generate 
    ahbram0 : ahbram generic map (hmask => 16#fff#,
    pipe => 0 ,
    maccsz => AHBDW,
    scantest => 0,
    endianness => GRLIB_CONFIG_ARRAY(grlib_little_endian),
    hindex => 0 , 0 => CFG_AHBRADDR, 
      tech => CFG_MEMTECH, kbytes => CFG_AHBRSZ)
    port map ( rstn, clkm, ahbsi, ahbso);
  end generate;

  nram : if CFG_AHBRAMEN = 0 generate ahbso(7) <= ahbs_none; end generate;

  -----------------------------------------------------------------------
  ---  AHB ROM ----------------------------------------------------------
  -----------------------------------------------------------------------

--  brom : entity work.ahbrom
--    generic map (
--      hindex  => 1,
--      haddr   => 16#000#,
--      pipe    => 0)
--    port map (
--      rst     => rstn,
--      clk     => clkm,
--      ahbsi   => ahbsi,
--      ahbso   => ahbso(1));
--    	
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
  
  vcc <= '1'; 
  gnd <= '0';
  cgi.pllctrl <= "00"; cgi.pllrst <= rstraw;

  pllref_pad : clkpad generic map (tech => padtech) port map (pllref, cgi.pllref); 
  clk_pad : clkpad generic map (tech => padtech) port map (clk, lclk); 

  clkgen0 : clkgen              -- clock generator
    generic map (clktech, CFG_CLKMUL, CFG_CLKDIV, CFG_SDEN, 
        CFG_INVCLK, CFG_GRPCI2_MASTER+CFG_GRPCI2_TARGET, CFG_PCIDLL, CFG_PCISYSCLK, BOARD_FREQ)
    port map (lclk, pci_lclk, clkm, open, open, sdclkl, pciclk, cgi, cgo);

  resetn_pad : inpad generic map (tech => padtech) port map (resetn, lresetn);
  
  rst0 : rstgen                 -- reset generator
    port map (lresetn, clkm, clklock, rstn, rstraw);
  
  clklock <= cgo.clklock;
   
    
end rtl;

