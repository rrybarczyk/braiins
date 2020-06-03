----------------------------------------------------------------------------------------------------
-- Copyright (C) 2020  Braiins Systems s.r.o.
--
-- This file is part of Braiins Open-Source Initiative (BOSI).
--
-- BOSI is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.
--
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
--
-- You should have received a copy of the GNU General Public License
-- along with this program.  If not, see <https://www.gnu.org/licenses/>.
--
-- Please, keep in mind that we may also license BOSI or any part thereof
-- under a proprietary license. For more information on the terms and conditions
-- of such proprietary license or if you have any other questions, please
-- contact us at opensource@braiins.com.
----------------------------------------------------------------------------------------------------
-- Project Name:   Braiins OS
-- Description:    AXI Interface of Glitch Monitor IP core
--
-- Engineer:       Marian Pristach
-- Revision:       1.0.0 (25.05.2020)
-- Comments:
----------------------------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity glitch_monitor_S_AXI is
    generic (
        -- Users to add parameters here
        C_CHANNELS            : integer range 3 to 14;

        -- User parameters ends
        -- Do not modify the parameters beyond this line

        -- Width of S_AXI data bus
        C_S_AXI_DATA_WIDTH    : integer := 32;
        -- Width of S_AXI address bus
        C_S_AXI_ADDR_WIDTH    : integer := 7
    );
    port (
        -- Users to add ports here

        -- Input signals
        sig_in         : in std_logic_vector(C_CHANNELS-1 downto 0);

        -- User ports ends
        -- Do not modify the ports beyond this line

        -- Global Clock Signal
        S_AXI_ACLK     : in std_logic;
        -- Global Reset Signal. This Signal is Active LOW
        S_AXI_ARESETN  : in std_logic;
        -- Write address (issued by master, acceped by Slave)
        S_AXI_AWADDR   : in std_logic_vector(C_S_AXI_ADDR_WIDTH-1 downto 0);
        -- Write channel Protection type. This signal indicates the
            -- privilege and security level of the transaction, and whether
            -- the transaction is a data access or an instruction access.
        S_AXI_AWPROT   : in std_logic_vector(2 downto 0);
        -- Write address valid. This signal indicates that the master signaling
            -- valid write address and control information.
        S_AXI_AWVALID  : in std_logic;
        -- Write address ready. This signal indicates that the slave is ready
            -- to accept an address and associated control signals.
        S_AXI_AWREADY  : out std_logic;
        -- Write data (issued by master, acceped by Slave)
        S_AXI_WDATA    : in std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
        -- Write strobes. This signal indicates which byte lanes hold
            -- valid data. There is one write strobe bit for each eight
            -- bits of the write data bus.
        S_AXI_WSTRB    : in std_logic_vector((C_S_AXI_DATA_WIDTH/8)-1 downto 0);
        -- Write valid. This signal indicates that valid write
            -- data and strobes are available.
        S_AXI_WVALID   : in std_logic;
        -- Write ready. This signal indicates that the slave
            -- can accept the write data.
        S_AXI_WREADY   : out std_logic;
        -- Write response. This signal indicates the status
            -- of the write transaction.
        S_AXI_BRESP    : out std_logic_vector(1 downto 0);
        -- Write response valid. This signal indicates that the channel
            -- is signaling a valid write response.
        S_AXI_BVALID   : out std_logic;
        -- Response ready. This signal indicates that the master
            -- can accept a write response.
        S_AXI_BREADY   : in std_logic;
        -- Read address (issued by master, acceped by Slave)
        S_AXI_ARADDR   : in std_logic_vector(C_S_AXI_ADDR_WIDTH-1 downto 0);
        -- Protection type. This signal indicates the privilege
            -- and security level of the transaction, and whether the
            -- transaction is a data access or an instruction access.
        S_AXI_ARPROT   : in std_logic_vector(2 downto 0);
        -- Read address valid. This signal indicates that the channel
            -- is signaling valid read address and control information.
        S_AXI_ARVALID  : in std_logic;
        -- Read address ready. This signal indicates that the slave is
            -- ready to accept an address and associated control signals.
        S_AXI_ARREADY  : out std_logic;
        -- Read data (issued by slave)
        S_AXI_RDATA    : out std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
        -- Read response. This signal indicates the status of the
            -- read transfer.
        S_AXI_RRESP    : out std_logic_vector(1 downto 0);
        -- Read valid. This signal indicates that the channel is
            -- signaling the required read data.
        S_AXI_RVALID   : out std_logic;
        -- Read ready. This signal indicates that the master can
            -- accept the read data and response information.
        S_AXI_RREADY   : in std_logic
    );
end glitch_monitor_S_AXI;

architecture arch_imp of glitch_monitor_S_AXI is

    -- AXI4LITE signals
    signal axi_awaddr   : std_logic_vector(C_S_AXI_ADDR_WIDTH-1 downto 0);
    signal axi_awready  : std_logic;
    signal axi_wready   : std_logic;
    signal axi_bresp    : std_logic_vector(1 downto 0);
    signal axi_bvalid   : std_logic;
    signal axi_araddr   : std_logic_vector(C_S_AXI_ADDR_WIDTH-1 downto 0);
    signal axi_arready  : std_logic;
    signal axi_rdata    : std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
    signal axi_rresp    : std_logic_vector(1 downto 0);
    signal axi_rvalid   : std_logic;

    -- Example-specific design signals
    -- local parameter for addressing 32 bit / 64 bit C_S_AXI_DATA_WIDTH
    -- ADDR_LSB is used for addressing 32/64 bit registers/memories
    -- ADDR_LSB = 2 for 32 bits (n downto 2)
    -- ADDR_LSB = 3 for 64 bits (n downto 3)
    constant ADDR_LSB  : integer := (C_S_AXI_DATA_WIDTH/32)+ 1;
    constant OPT_MEM_ADDR_BITS : integer := 4;
    ------------------------------------------------
    ---- Signals for user logic register space example
    --------------------------------------------------
    ---- Number of Slave Registers 32
    signal slv_ctrl_reg : std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
    signal slv_reg1     : std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
    signal slv_reg2     : std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
    signal slv_reg3     : std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
    signal slv_reg_rden : std_logic;
    signal slv_reg_wren : std_logic;
    signal reg_data_out : std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
    signal aw_en        : std_logic;

    ------------------------------------------------------------------------------------------------
    -- definition of array types
    type glitch_cnt_array_t is array(0 to 13) of std_logic_vector(31 downto 0);
    type glitch_width_array_t is array(0 to 13) of std_logic_vector(2 downto 0);

    -- glitch result arrays
    signal glitch_cnt_array   : glitch_cnt_array_t;
    signal glitch_width_array : glitch_width_array_t;


begin
    -- I/O Connections assignments

    S_AXI_AWREADY <= axi_awready;
    S_AXI_WREADY  <= axi_wready;
    S_AXI_BRESP   <= axi_bresp;
    S_AXI_BVALID  <= axi_bvalid;
    S_AXI_ARREADY <= axi_arready;
    S_AXI_RDATA   <= axi_rdata;
    S_AXI_RRESP   <= axi_rresp;
    S_AXI_RVALID  <= axi_rvalid;
    -- Implement axi_awready generation
    -- axi_awready is asserted for one S_AXI_ACLK clock cycle when both
    -- S_AXI_AWVALID and S_AXI_WVALID are asserted. axi_awready is
    -- de-asserted when reset is low.

    process (S_AXI_ACLK)
    begin
      if rising_edge(S_AXI_ACLK) then
        if S_AXI_ARESETN = '0' then
          axi_awready <= '0';
          aw_en <= '1';
        else
          if (axi_awready = '0' and S_AXI_AWVALID = '1' and S_AXI_WVALID = '1' and aw_en = '1') then
            -- slave is ready to accept write address when
            -- there is a valid write address and write data
            -- on the write address and data bus. This design
            -- expects no outstanding transactions.
            axi_awready <= '1';
            elsif (S_AXI_BREADY = '1' and axi_bvalid = '1') then
                aw_en <= '1';
                axi_awready <= '0';
          else
            axi_awready <= '0';
          end if;
        end if;
      end if;
    end process;

    -- Implement axi_awaddr latching
    -- This process is used to latch the address when both
    -- S_AXI_AWVALID and S_AXI_WVALID are valid.

    process (S_AXI_ACLK)
    begin
      if rising_edge(S_AXI_ACLK) then
        if S_AXI_ARESETN = '0' then
          axi_awaddr <= (others => '0');
        else
          if (axi_awready = '0' and S_AXI_AWVALID = '1' and S_AXI_WVALID = '1' and aw_en = '1') then
            -- Write Address latching
            axi_awaddr <= S_AXI_AWADDR;
          end if;
        end if;
      end if;
    end process;

    -- Implement axi_wready generation
    -- axi_wready is asserted for one S_AXI_ACLK clock cycle when both
    -- S_AXI_AWVALID and S_AXI_WVALID are asserted. axi_wready is
    -- de-asserted when reset is low.

    process (S_AXI_ACLK)
    begin
      if rising_edge(S_AXI_ACLK) then
        if S_AXI_ARESETN = '0' then
          axi_wready <= '0';
        else
          if (axi_wready = '0' and S_AXI_WVALID = '1' and S_AXI_AWVALID = '1' and aw_en = '1') then
              -- slave is ready to accept write data when
              -- there is a valid write address and write data
              -- on the write address and data bus. This design
              -- expects no outstanding transactions.
              axi_wready <= '1';
          else
            axi_wready <= '0';
          end if;
        end if;
      end if;
    end process;

    -- Implement memory mapped register select and write logic generation
    -- The write data is accepted and written to memory mapped registers when
    -- axi_awready, S_AXI_WVALID, axi_wready and S_AXI_WVALID are asserted. Write strobes are used to
    -- select byte enables of slave registers while writing.
    -- These registers are cleared when reset (active low) is applied.
    -- Slave register write enable is asserted when valid address and data are available
    -- and the slave is ready to accept the write address and write data.
    slv_reg_wren <= axi_wready and S_AXI_WVALID and axi_awready and S_AXI_AWVALID ;

    process (S_AXI_ACLK)
    variable loc_addr :std_logic_vector(OPT_MEM_ADDR_BITS downto 0);
    begin
      if rising_edge(S_AXI_ACLK) then
        if S_AXI_ARESETN = '0' then
          slv_ctrl_reg <= (others => '0');
          slv_reg1 <= (others => '0');
          slv_reg2 <= (others => '0');
          slv_reg3 <= (others => '0');
        else

          -- clear counter reset request
          slv_ctrl_reg(0) <= '0';

          loc_addr := axi_awaddr(ADDR_LSB + OPT_MEM_ADDR_BITS downto ADDR_LSB);
          if (slv_reg_wren = '1') then
            case loc_addr is
              when b"00000" =>
                for byte_index in 0 to (C_S_AXI_DATA_WIDTH/8-1) loop
                  if ( S_AXI_WSTRB(byte_index) = '1' ) then
                    -- Respective byte enables are asserted as per write strobes
                    -- slave registor 0
                    slv_ctrl_reg(byte_index*8+7 downto byte_index*8) <= S_AXI_WDATA(byte_index*8+7 downto byte_index*8);
                  end if;
                end loop;
              when b"00001" =>
                for byte_index in 0 to (C_S_AXI_DATA_WIDTH/8-1) loop
                  if ( S_AXI_WSTRB(byte_index) = '1' ) then
                    -- Respective byte enables are asserted as per write strobes
                    -- slave registor 1
                    slv_reg1(byte_index*8+7 downto byte_index*8) <= S_AXI_WDATA(byte_index*8+7 downto byte_index*8);
                  end if;
                end loop;
              when b"00010" =>
                for byte_index in 0 to (C_S_AXI_DATA_WIDTH/8-1) loop
                  if ( S_AXI_WSTRB(byte_index) = '1' ) then
                    -- Respective byte enables are asserted as per write strobes
                    -- slave registor 2
                    slv_reg2(byte_index*8+7 downto byte_index*8) <= S_AXI_WDATA(byte_index*8+7 downto byte_index*8);
                  end if;
                end loop;
              when b"00011" =>
                for byte_index in 0 to (C_S_AXI_DATA_WIDTH/8-1) loop
                  if ( S_AXI_WSTRB(byte_index) = '1' ) then
                    -- Respective byte enables are asserted as per write strobes
                    -- slave registor 3
                    slv_reg3(byte_index*8+7 downto byte_index*8) <= S_AXI_WDATA(byte_index*8+7 downto byte_index*8);
                  end if;
                end loop;
              when others =>
            end case;
          end if;
        end if;
      end if;
    end process;

    -- Implement write response logic generation
    -- The write response and response valid signals are asserted by the slave
    -- when axi_wready, S_AXI_WVALID, axi_wready and S_AXI_WVALID are asserted.
    -- This marks the acceptance of address and indicates the status of
    -- write transaction.

    process (S_AXI_ACLK)
    begin
      if rising_edge(S_AXI_ACLK) then
        if S_AXI_ARESETN = '0' then
          axi_bvalid  <= '0';
          axi_bresp   <= "00"; --need to work more on the responses
        else
          if (axi_awready = '1' and S_AXI_AWVALID = '1' and axi_wready = '1' and S_AXI_WVALID = '1' and axi_bvalid = '0'  ) then
            axi_bvalid <= '1';
            axi_bresp  <= "00";
          elsif (S_AXI_BREADY = '1' and axi_bvalid = '1') then   --check if bready is asserted while bvalid is high)
            axi_bvalid <= '0';                                 -- (there is a possibility that bready is always asserted high)
          end if;
        end if;
      end if;
    end process;

    -- Implement axi_arready generation
    -- axi_arready is asserted for one S_AXI_ACLK clock cycle when
    -- S_AXI_ARVALID is asserted. axi_awready is
    -- de-asserted when reset (active low) is asserted.
    -- The read address is also latched when S_AXI_ARVALID is
    -- asserted. axi_araddr is reset to zero on reset assertion.

    process (S_AXI_ACLK)
    begin
      if rising_edge(S_AXI_ACLK) then
        if S_AXI_ARESETN = '0' then
          axi_arready <= '0';
          axi_araddr  <= (others => '1');
        else
          if (axi_arready = '0' and S_AXI_ARVALID = '1') then
            -- indicates that the slave has acceped the valid read address
            axi_arready <= '1';
            -- Read Address latching
            axi_araddr  <= S_AXI_ARADDR;
          else
            axi_arready <= '0';
          end if;
        end if;
      end if;
    end process;

    -- Implement axi_arvalid generation
    -- axi_rvalid is asserted for one S_AXI_ACLK clock cycle when both
    -- S_AXI_ARVALID and axi_arready are asserted. The slave registers
    -- data are available on the axi_rdata bus at this instance. The
    -- assertion of axi_rvalid marks the validity of read data on the
    -- bus and axi_rresp indicates the status of read transaction.axi_rvalid
    -- is deasserted on reset (active low). axi_rresp and axi_rdata are
    -- cleared to zero on reset (active low).
    process (S_AXI_ACLK)
    begin
      if rising_edge(S_AXI_ACLK) then
        if S_AXI_ARESETN = '0' then
          axi_rvalid <= '0';
          axi_rresp  <= "00";
        else
          if (axi_arready = '1' and S_AXI_ARVALID = '1' and axi_rvalid = '0') then
            -- Valid read data is available at the read data bus
            axi_rvalid <= '1';
            axi_rresp  <= "00"; -- 'OKAY' response
          elsif (axi_rvalid = '1' and S_AXI_RREADY = '1') then
            -- Read data is accepted by the master
            axi_rvalid <= '0';
          end if;
        end if;
      end if;
    end process;

    -- Implement memory mapped register select and read logic generation
    -- Slave register read enable is asserted when valid address is available
    -- and the slave is ready to accept the read address.
    slv_reg_rden <= axi_arready and S_AXI_ARVALID and (not axi_rvalid) ;

    process (slv_ctrl_reg, slv_reg1, slv_reg2, slv_reg3, glitch_cnt_array, glitch_width_array, axi_araddr)
    variable loc_addr :std_logic_vector(OPT_MEM_ADDR_BITS downto 0);
    begin
        -- Address decoding for reading registers
        loc_addr := axi_araddr(ADDR_LSB + OPT_MEM_ADDR_BITS downto ADDR_LSB);
        case loc_addr is
          when b"00000" =>
            reg_data_out <= slv_ctrl_reg;
          when b"00001" =>
            reg_data_out <= slv_reg1;
          when b"00010" =>
            reg_data_out <= slv_reg2;
          when b"00011" =>
            reg_data_out <= slv_reg3;
          when b"00100" =>
            reg_data_out <= glitch_cnt_array(0);
          when b"00101" =>
            reg_data_out <= std_logic_vector(resize(unsigned(glitch_width_array(0)), 32));
          when b"00110" =>
            reg_data_out <= glitch_cnt_array(1);
          when b"00111" =>
            reg_data_out <= std_logic_vector(resize(unsigned(glitch_width_array(1)), 32));
          when b"01000" =>
            reg_data_out <= glitch_cnt_array(2);
          when b"01001" =>
            reg_data_out <= std_logic_vector(resize(unsigned(glitch_width_array(2)), 32));
          when b"01010" =>
            reg_data_out <= glitch_cnt_array(3);
          when b"01011" =>
            reg_data_out <= std_logic_vector(resize(unsigned(glitch_width_array(3)), 32));
          when b"01100" =>
            reg_data_out <= glitch_cnt_array(4);
          when b"01101" =>
            reg_data_out <= std_logic_vector(resize(unsigned(glitch_width_array(4)), 32));
          when b"01110" =>
            reg_data_out <= glitch_cnt_array(5);
          when b"01111" =>
            reg_data_out <= std_logic_vector(resize(unsigned(glitch_width_array(5)), 32));
          when b"10000" =>
            reg_data_out <= glitch_cnt_array(6);
          when b"10001" =>
            reg_data_out <= std_logic_vector(resize(unsigned(glitch_width_array(6)), 32));
          when b"10010" =>
            reg_data_out <= glitch_cnt_array(7);
          when b"10011" =>
            reg_data_out <= std_logic_vector(resize(unsigned(glitch_width_array(7)), 32));
          when b"10100" =>
            reg_data_out <= glitch_cnt_array(8);
          when b"10101" =>
            reg_data_out <= std_logic_vector(resize(unsigned(glitch_width_array(8)), 32));
          when b"10110" =>
            reg_data_out <= glitch_cnt_array(9);
          when b"10111" =>
            reg_data_out <= std_logic_vector(resize(unsigned(glitch_width_array(9)), 32));
          when b"11000" =>
            reg_data_out <= glitch_cnt_array(10);
          when b"11001" =>
            reg_data_out <= std_logic_vector(resize(unsigned(glitch_width_array(10)), 32));
          when b"11010" =>
            reg_data_out <= glitch_cnt_array(11);
          when b"11011" =>
            reg_data_out <= std_logic_vector(resize(unsigned(glitch_width_array(11)), 32));
          when b"11100" =>
            reg_data_out <= glitch_cnt_array(12);
          when b"11101" =>
            reg_data_out <= std_logic_vector(resize(unsigned(glitch_width_array(12)), 32));
          when b"11110" =>
            reg_data_out <= glitch_cnt_array(13);
          when b"11111" =>
            reg_data_out <= std_logic_vector(resize(unsigned(glitch_width_array(13)), 32));
          when others =>
            reg_data_out  <= (others => '0');
        end case;
    end process;

    -- Output register or memory read data
    process( S_AXI_ACLK ) is
    begin
      if (rising_edge (S_AXI_ACLK)) then
        if ( S_AXI_ARESETN = '0' ) then
          axi_rdata  <= (others => '0');
        else
          if (slv_reg_rden = '1') then
            -- When there is a valid read address (S_AXI_ARVALID) with
            -- acceptance of read address by the slave (axi_arready),
            -- output the read dada
            -- Read address mux
              axi_rdata <= reg_data_out;     -- register read data
          end if;
        end if;
      end if;
    end process;


    ------------------------------------------------------------------------------------------------
    -- glitch detector - SCL
    i_detector_scl: entity work.glitch_detector
        generic map (
            C_MAX_WIDTH  => 7      -- max. width of glitch to detect in clk periods
        )
        port map (
            clk          => S_AXI_ACLK,
            rst          => S_AXI_ARESETN,

            -- Control signals
            enable       => '1',
            clear        => slv_ctrl_reg(0),

            -- Input signal
            sig_in       => sig_in(0),

            -- Output data
            glitch_cnt   => glitch_cnt_array(0),
            glitch_width => glitch_width_array(0)
        );

    -- glitch detector - SDA, signal is gated by SCL (glitch is valid only when SCL = '1')
    i_detector_sda: entity work.glitch_detector
        generic map (
            C_MAX_WIDTH  => 7      -- max. width of glitch to detect in clk periods
        )
        port map (
            clk          => S_AXI_ACLK,
            rst          => S_AXI_ARESETN,

            -- Control signals
            enable       => sig_in(0),
            clear        => slv_ctrl_reg(0),

            -- Input signal
            sig_in       => sig_in(1),

            -- Output data
            glitch_cnt   => glitch_cnt_array(1),
            glitch_width => glitch_width_array(1)
        );

    ------------------------------------------------------------------------------------------------
    -- glitch detectors
    g_detectors: for i in 2 to C_CHANNELS-1 generate
        i_detector: entity work.glitch_detector
            generic map (
                C_MAX_WIDTH  => 3      -- max. width of glitch to detect in clk periods
            )
            port map (
                clk          => S_AXI_ACLK,
                rst          => S_AXI_ARESETN,

                -- Control signals
                enable       => '1',
                clear        => slv_ctrl_reg(0),

                -- Input signal
                sig_in       => sig_in(i),

                -- Output data
                glitch_cnt   => glitch_cnt_array(i),
                glitch_width => glitch_width_array(i)
            );
    end generate g_detectors;

    -- other signals tied to zero
    g_zeros: for i in C_CHANNELS to 13 generate
        glitch_cnt_array(i) <= (others => '0');
        glitch_width_array(i) <= (others => '0');
    end generate g_zeros;

end arch_imp;
