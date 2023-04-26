-- cpu.vhd: Simple 8-bit CPU (BrainFuck interpreter)
-- Copyright (C) 2022 Brno University of Technology,
--                    Faculty of Information Technology
-- Author(s): jmeno <login AT stud.fit.vutbr.cz>
--
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

-- ----------------------------------------------------------------------------
--                        Entity declaration
-- ----------------------------------------------------------------------------
entity cpu is
 port (
   CLK   : in std_logic;  -- hodinovy signal
   RESET : in std_logic;  -- asynchronni reset procesoru
   EN    : in std_logic;  -- povoleni cinnosti procesoru
 
   -- synchronni pamet RAM
   DATA_ADDR  : out std_logic_vector(12 downto 0); -- adresa do pameti
   DATA_WDATA : out std_logic_vector(7 downto 0); -- mem[DATA_ADDR] <- DATA_WDATA pokud DATA_EN='1'
   DATA_RDATA : in std_logic_vector(7 downto 0);  -- DATA_RDATA <- ram[DATA_ADDR] pokud DATA_EN='1'
   DATA_RDWR  : out std_logic;                    -- cteni (0) / zapis (1)
   DATA_EN    : out std_logic;                    -- povoleni cinnosti
   
   -- vstupni port
   IN_DATA   : in std_logic_vector(7 downto 0);   -- IN_DATA <- stav klavesnice pokud IN_VLD='1' a IN_REQ='1'
   IN_VLD    : in std_logic;                      -- data platna
   IN_REQ    : out std_logic;                     -- pozadavek na vstup data
   
   -- vystupni port
   OUT_DATA : out  std_logic_vector(7 downto 0);  -- zapisovana data
   OUT_BUSY : in std_logic;                       -- LCD je zaneprazdnen (1), nelze zapisovat
   OUT_WE   : out std_logic                       -- LCD <- OUT_DATA pokud OUT_WE='1' a OUT_BUSY='0'
 );
end cpu;


-- ----------------------------------------------------------------------------
--                      Architecture declaration
-- ----------------------------------------------------------------------------
architecture behavioral of cpu is

  -- signaly
  signal cnt_reg : std_logic_vector(7 downto 0);
  signal cnt_inc : std_logic;
  signal cnt_dec : std_logic;

  signal pc_reg  : std_logic_vector(11 downto 0);
  signal pc_inc  : std_logic;
  signal pc_dec  : std_logic;

  signal ptr_reg : std_logic_vector(11 downto 0);
  signal ptr_inc : std_logic;
  signal ptr_dec : std_logic;

  signal mx1_sel : std_logic;
  signal mx2_sel : std_logic_vector(1 downto 0);

  -- stavy
  type FSM_STATE is (
    fsm_start,
    fsm_fetch,
    fsm_decode,

    fsm_ptr_inc,
    fsm_ptr_dec,
    fsm_val_inc_start,
    fsm_val_inc_do,
    fsm_val_dec_start,
    fsm_val_dec_do,
    fsm_while_begin,
    fsm_while_begin_do,
    fsm_while_begin_cycle,
    fsm_while_end_do,
    fsm_while_end_cycle,
    fsm_dowhile_begin,
    fsm_dowhile_end,
    fsm_dowhile_end_do,
    fsm_write_req,
    fsm_write,
    fsm_read_req,
    fsm_read,
    fsm_other,
    fsm_finish
  );
  signal current_state : FSM_STATE := fsm_start;
  signal next_state : FSM_STATE;


begin

  --Program Counter 
  pc: process (CLK, RESET, pc_reg, pc_inc, pc_dec) is 
  begin
      if RESET = '1' then 
          pc_reg <= (others => '0');
      elsif rising_edge(CLK) then 
          if pc_inc = '1' then 
              pc_reg <= pc_reg + 1;
          elsif pc_dec = '1' then 
              pc_reg <= pc_reg - 1;
          end if;
      end if; 
  end process;


  --Pointer 
  ptr: process (CLK, RESET, ptr_reg, ptr_inc, ptr_dec) is
  begin
      if RESET = '1' then
          ptr_reg <= (others => '0');
      elsif rising_edge(CLK) then
          if ptr_inc = '1' then
              ptr_reg <= ptr_reg + 1;
          elsif ptr_dec = '1' then
              ptr_reg <= ptr_reg - 1;
          end if;
      end if;
  end process;


  --Counter
  cnt: process (CLK, RESET, cnt_reg, cnt_inc, cnt_dec) is
  begin
      if RESET = '1' then
          cnt_reg <= (others => '0');
      elsif rising_edge(CLK) then
          if cnt_inc = '1' then
              cnt_reg <= cnt_reg + 1;
          elsif cnt_dec = '1' then
              cnt_reg <= cnt_reg - 1;
          end if;
      end if;
  end process;


  --Multiplexor 1
  mx1: process (mx1_sel, pc_reg, ptr_reg) is
  begin
    case mx1_sel is 
        when '0' => DATA_ADDR <= "0" & pc_reg;
        when '1' => DATA_ADDR <= "1" & ptr_reg;
        when others => DATA_ADDR <= (others => '0');
    end case;
  end process;


  --Multiplexor 2
  mx2: process (mx2_sel, IN_DATA, DATA_RDATA) is
  begin
    case mx2_sel is
        when "00" => DATA_WDATA <= IN_DATA;
        when "01" => DATA_WDATA <= (DATA_RDATA + 1);
        when "10" => DATA_WDATA <= (DATA_RDATA - 1);
        when others => DATA_WDATA <= (others => '0');
    end  case;
  end process;  


  --Current State Logic
  current_state_logic: process (CLK, RESET) is 
  begin
    if RESET = '1' then
        current_state <= fsm_start;
    elsif rising_edge(CLK) then 
        current_state <= next_state;
    end if;
  end process;


  --FSM
  fsm: process (CLK, RESET, EN, DATA_RDATA, IN_VLD, OUT_BUSY, current_state, next_state) is
  begin 
    --Initialize values
    pc_inc <= '0';
    pc_dec <= '0';

    ptr_inc <= '0';
    ptr_dec <= '0';
    
    cnt_inc <= '0';
    cnt_dec <= '0';

    mx1_sel <= '0';
    mx2_sel <= "00";

    IN_REQ <= '0';
    OUT_WE <= '0';
    DATA_EN <= '0';
    DATA_RDWR <= '0';

    --FSM logic
    if EN = '1' then
        case current_state is
            --Start, Fetch, Decode
            when fsm_start => 
                next_state <= fsm_fetch;

            when fsm_fetch => 
                DATA_EN <= '1';
                next_state <= fsm_decode;
            when fsm_decode => 
                    case DATA_RDATA is
                        when X"3E" => next_state <= fsm_ptr_inc;       -- >
                        when X"3C" => next_state <= fsm_ptr_dec;       -- <
                        when X"2B" => next_state <= fsm_val_inc_start;       -- +  
                        when X"2D" => next_state <= fsm_val_dec_start;       -- -
                        when X"5B" => next_state <= fsm_while_begin;   -- [
                        when X"5D" => next_state <= fsm_while_end_do;     -- ]
                        when X"28" => next_state <= fsm_dowhile_begin; -- (
                        when X"29" => next_state <= fsm_dowhile_end;   -- )
                        when X"2E" => next_state <= fsm_write_req;         -- .
                        when X"2C" => next_state <= fsm_read_req;          -- ,
                        when X"00" => next_state <= fsm_finish;        -- return
                        when others => next_state <= fsm_other;       -- other chars
                    end case;
            --Reading .b code
            -- >
            when fsm_ptr_inc =>
                ptr_inc <= '1';
                pc_inc <= '1';
                next_state <= fsm_fetch;

            -- <
            when fsm_ptr_dec =>
                ptr_dec <= '1';
                pc_inc <= '1';
                next_state <= fsm_fetch;

            -- +
            when fsm_val_inc_start =>
                DATA_EN <= '1';
                mx1_sel <= '1';
                next_state <= fsm_val_inc_do;

            when fsm_val_inc_do =>
                DATA_EN <= '1';
                DATA_RDWR <= '1';
                mx1_sel <= '1';
                mx2_sel <= "01"; 
                pc_inc <= '1';
                next_state <= fsm_fetch;

            -- -
            when fsm_val_dec_start => 
                DATA_EN <= '1';
                mx1_sel <= '1';
                next_state <= fsm_val_dec_do;

            when fsm_val_dec_do =>
                DATA_EN <= '1';
                DATA_RDWR <= '1';
                mx1_sel <= '1';
                mx2_sel <= "10";
                pc_inc <= '1';
                next_state <= fsm_fetch;

            -- [
            when fsm_while_begin =>
                pc_inc <= '1';
                next_state <= fsm_while_begin_do;

            when fsm_while_begin_do =>
                DATA_EN <= '1';
                DATA_RDWR <= '0';
                mx1_sel <= '1';
                if DATA_RDATA /= X"00" then
                    next_state <= fsm_fetch;
                else 
                    cnt_inc <= '1';
                    next_state <= fsm_while_begin_cycle;
                end if;


            when fsm_while_begin_cycle =>
                DATA_EN <= '1';
                DATA_RDWR <= '0';
                if DATA_RDATA /= X"5D" then
                    pc_inc <= '1';
                    next_state <= fsm_while_begin_cycle;
                else
                    cnt_dec <= '1';
                    if (cnt_reg - 1) /= X"00" then
                        pc_inc <= '1';
                        next_state <= fsm_while_begin_cycle;
                    else 
                        next_state <= fsm_fetch;
                    end if;
                end if;
            
            -- ]
            
            when fsm_while_end_do =>
                DATA_EN <= '1';
                DATA_RDWR <= '0';
                mx1_sel <= '1';
                next_state <= fsm_while_end_cycle;

            when fsm_while_end_cycle =>
                if DATA_RDATA /= X"00" then
                    DATA_EN <= '1'; 
                    if DATA_RDATA = X"5D" then
                        cnt_inc <= '1';
                        pc_dec <= '1';
                        next_state <= fsm_while_end_cycle;
                    elsif DATA_RDATA = X"5B" then
                        cnt_dec <= '1';
                        if (cnt_reg - 1) = X"00" then
                            pc_inc <= '1';
                            next_state <= fsm_fetch;
                        else 
                            pc_dec <= '1';
                            next_state <= fsm_while_end_cycle;
                        end if;
                    else
                        pc_dec <= '1';
                        next_state <= fsm_while_end_cycle;
                    end if;
                else --break out of the loop
                    pc_inc <= '1';
                    next_state <= fsm_fetch;
                end if;

            -- (
            when fsm_dowhile_begin =>
                pc_inc <= '1';
                next_state <= fsm_fetch;

            -- )
            when fsm_dowhile_end => 
                DATA_EN <= '1';
                DATA_RDWR <= '0';
                mx1_sel <= '1';
                next_state <= fsm_dowhile_end_do;

            when fsm_dowhile_end_do =>
                if DATA_RDATA /= X"00" then 
                    DATA_EN <= '1';
                    if DATA_RDATA /= X"28" then
                        pc_dec <= '1';
                        next_state <=fsm_dowhile_end_do;
                    elsif DATA_RDATA = X"28" then   
                        pc_inc <= '1';
                        next_state <= fsm_fetch;
                    end if;
                else --break out of the loop
                    pc_inc <= '1';
                    next_state <= fsm_fetch; 
                end if;


            -- .
            when fsm_write_req => 
                if OUT_BUSY = '1' then 
                    next_state <= fsm_write_req;
                elsif OUT_BUSY = '0' then 
                    DATA_EN <= '1';
                    mx1_sel <= '1';
                   next_state <= fsm_write;
                end if;
                


            when fsm_write =>
                if OUT_BUSY = '1' then
                    next_state <= fsm_write_req;
                elsif OUT_BUSY = '0' then
                    OUT_WE <= '1';
                    OUT_DATA <= DATA_RDATA;
                    next_state <= fsm_fetch;
                    pc_inc <= '1';
                end if;
                

            -- ,
            when fsm_read_req =>
                IN_REQ <= '1';
                if IN_VLD = '0' then
                    next_state <= fsm_read_req;
                elsif IN_VLD = '1' then
                    next_state <= fsm_read;
                end if;

            when fsm_read =>
                DATA_EN <= '1';
                DATA_RDWR <= '1';
                mx1_sel <= '1';
                pc_inc <= '1';
                next_state <= fsm_fetch;

            -- other (comments)
            when fsm_other =>
                pc_inc <= '1';
                next_state <= fsm_fetch;

            when fsm_finish =>
                next_state <= fsm_finish;
        end case;
    end if;
  end process;
end behavioral;