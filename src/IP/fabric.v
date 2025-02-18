`timescale 1ns / 1ns
`include "../../src/configs.vh"

module fabric #(
  parameter  DATA_SIZE    = 32,
  parameter  ADDR_SIZE    = 4,
  parameter  ADDR         = 0,
  parameter  NODES_NUM    = 9,
  parameter  PACKS_TO_GEN = 10,
  parameter  MAX_PACK_LEN = 10,
  parameter  DEBUG        = 1'b0,
  parameter  FREQ         = 25,
  localparam BUS_SIZE = DATA_SIZE + ADDR_SIZE + 1
) (
  input                     clk,
  input                     a_rst,
  input                     in_r,
  input                     out_w,
  input      [BUS_SIZE-1:0] data_i,
  output reg                in_w,
  output reg                out_r,
  output reg [BUS_SIZE-1:0] data_o
);
  // generating data
  localparam RESET = 3'h0, PACK_GEN = 3'h1, FLIT_GEN = 3'h2, FLIT_SEND = 3'h3, GEN_FINISH = 3'h4;

  integer generated_packs;
  integer pack_len;
  integer freq_cntr;

  reg [2:0] gen_state;
  reg [ADDR_SIZE-1:0] dest_addr;
  reg [DATA_SIZE-1:0] gen_data;

  function [4*8-1:0] itoa;
    input [31:0] int;
    integer i;
      for (i = 0; i < 4; i = i + 1)
        case (int[i*4+:4])
          4'h0: itoa[i*8+:8] = "0";
          4'h1: itoa[i*8+:8] = "1";
          4'h2: itoa[i*8+:8] = "2";
          4'h3: itoa[i*8+:8] = "3";
          4'h4: itoa[i*8+:8] = "4";
          4'h5: itoa[i*8+:8] = "5";
          4'h6: itoa[i*8+:8] = "6";
          4'h7: itoa[i*8+:8] = "7";
          4'h8: itoa[i*8+:8] = "8";
          4'h9: itoa[i*8+:8] = "9";
          4'ha: itoa[i*8+:8] = "a";
          4'hb: itoa[i*8+:8] = "b";
          4'hc: itoa[i*8+:8] = "c";
          4'hd: itoa[i*8+:8] = "d";
          4'he: itoa[i*8+:8] = "e";
          4'hf: itoa[i*8+:8] = "f";
          default: itoa[i*8+:8] = "0";
        endcase
  endfunction

  // open log file
  integer log_file;
  initial
    if (!DEBUG)
      begin
        log_file = $fopen({`LOGS_PATH, "/fabric_", itoa(ADDR)});
        #(2*`CLK_CNT+2) $fclose(log_file);
      end

  // generating data to send
  always @(posedge clk, posedge a_rst)
    begin
      if (!a_rst)
      case (gen_state)
        PACK_GEN:
          begin
            pack_len = $urandom % MAX_PACK_LEN;
            dest_addr = $urandom % NODES_NUM;
            if (dest_addr != ADDR)
              begin
                gen_state = FLIT_GEN;
                if (DEBUG)
                  $display("%5d|%3h|new package|len:%2h|addr:%3h", $time, ADDR, pack_len + 1, dest_addr);
                else
                  $fdisplay(log_file, "%5d|%3h|new package|len:%2h|addr:%3h", $time, ADDR, pack_len + 1, dest_addr);
              end
          end
        FLIT_GEN:
          if (out_w == 1'b0)
            if (freq_cntr - 1 == FREQ)
              begin
                freq_cntr = 0;
                out_r = 1'b1;
                gen_data = $urandom;
                data_o = {gen_data, (pack_len == 0 ? 1'b1 : 1'b0), dest_addr};  
                if (DEBUG)     
                  $display("%5d|%3h|new flit|%b", $time, ADDR, data_o);
                else
                  $fdisplay(log_file, "%5d|%3h|new flit|%b", $time, ADDR, data_o);
                gen_state = FLIT_SEND;
              end
            else
              freq_cntr = freq_cntr + 1;
        FLIT_SEND:
          if (out_w == 1'b1)
            begin
              out_r = 1'b0;
              if (DEBUG)
                $display("%5d|%3h|flit sended|%b", $time, ADDR, data_o);
              else
                $fdisplay(log_file, "%5d|%3h|flit sended|%b", $time, ADDR, data_o);
              if (pack_len == 0)
                  begin
                    if (DEBUG)
                      $display("%5d|%3h|package sended|%d", $time, ADDR, generated_packs);
                    else
                      $fdisplay(log_file, "%5d|%3h|package sended|%d", $time, ADDR, generated_packs);
                    generated_packs = generated_packs + 1;
                    if (generated_packs == PACKS_TO_GEN)
                      gen_state = GEN_FINISH;
                    else
                      gen_state = PACK_GEN;
                  end
              else
                begin
                  gen_state = FLIT_GEN;
                  pack_len  = pack_len - 1;
                end
            end
        GEN_FINISH:
          begin
            if (DEBUG)
              $display("%5d|%3h|finish generating|%d", $time, ADDR, generated_packs);
            else
              $fdisplay(log_file, "%5d|%3h|finish generating|%d", $time, ADDR, generated_packs);
          end
        default:
          gen_state = RESET;
      endcase
    end

  localparam WAIT = 2'h1, GET = 2'h2;
  reg [2:0] recv_state;
  integer recv_flits;
  integer wrong_packs;
  integer recv_packs;
  
  // receiving data
  always @(posedge clk, posedge a_rst)
    begin
      if (!a_rst)
      case (recv_state)
        WAIT:
          if (in_r == 1'b1)
            begin
              in_w       = 1'b1;
              recv_state = GET;
              recv_packs = 0;
              if (DEBUG)
                $display("%5d|%3h|wait for reading", $time, ADDR);
              else
                $fdisplay(log_file, "%5d|%3h|wait for reading", $time, ADDR);
            end
        GET:
          if (in_r == 1'b0)
            begin
              in_w = 1'b0;
              if (DEBUG)
                $display("%5d|%3h|recved flit|%b", $time, ADDR, recv_flits, data_i);
              else
                $fdisplay(log_file, "%5d|%3h|recved flit|%b", $time, ADDR, recv_flits, data_i);
              if (ADDR != data_i[ADDR_SIZE-1:0])  // if wrong address
                begin
                  if (DEBUG)
                    $display("%5d|%3h|recved wrong flit|real addr: %3h", $time, ADDR, data_i[ADDR_SIZE-1:0]);
                  else
                    $fdisplay(log_file, "%5d|%3h|recved wrong flit|real addr: %3h", $time, ADDR, data_i[ADDR_SIZE-1:0]);
                  wrong_packs = wrong_packs + 1;
                end
              if (data_i[ADDR_SIZE] == 1'b1)    // if last flit of a package
                begin
                  recv_packs = recv_packs + 1;
                  recv_flits = 0;
                  if (DEBUG)
                    $display("%5d|%3h|recved package|packeges:%d", $time, ADDR, recv_packs);
                  else
                    $fdisplay(log_file, "%5d|%3h|recved package|packeges:%d", $time, ADDR, recv_packs);
                end
              else
                recv_flits = recv_flits + 1;
              recv_state = WAIT;
            end
      endcase
    end

  // resetting
  always @(posedge clk, posedge a_rst)
    if (a_rst)
      begin
        out_r           <= 1'b0;
        gen_state       <= PACK_GEN;
        pack_len        <= 0;
        generated_packs <= 0;
        freq_cntr       <= 0;
        in_w            <= 1'b0;
        recv_state      <= WAIT;
        recv_flits      <= 0;
        wrong_packs     <= 0;
        if (DEBUG)
          $display("%5d|%3h|reset", $time, ADDR);
        else
          $fdisplay(log_file, "%5d|%3h|reset", $time, ADDR);
      end

endmodule // fabric
