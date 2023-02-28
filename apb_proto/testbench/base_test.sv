
/******************************************************************************************
* File Name:     base_test.sv
* Author:          wuqlan
* Email:           
* Date Created:    2023/2/28
* Description:
*
*
* Version:         0.1
****************************************************************************************/


`ifndef  BASE_TEST_SV
`define  BASE_TEST_SV

`include  "definition.sv"
`include  "apb_env.sv"
`include  "uvm_pkg.sv"

import  uvm_pkg::*;


class base_test extends uvm_test;

   apb_env   env;
   
   function new(string name = "base_test", uvm_component parent = null);
      super.new(name,parent);
   endfunction
   
   extern virtual function void build_phase(uvm_phase phase);
   extern virtual function void report_phase(uvm_phase phase);
   `uvm_component_utils(base_test)
endclass


function void base_test::build_phase(uvm_phase phase);
   super.build_phase(phase);
   env  =  apb_env::type_id::create("env", this);
endfunction

function void base_test::report_phase(uvm_phase phase);
   uvm_report_server server;
   int err_num;
   super.report_phase(phase);

   server = get_report_server();
   err_num = server.get_severity_count(UVM_ERROR);

   if (err_num != 0) begin
      $display("TEST CASE FAILED");
   end
   else begin
      $display("TEST CASE PASSED");
   end
endfunction

`endif


