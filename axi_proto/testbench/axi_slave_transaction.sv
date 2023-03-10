/**************************************************************************************
* File Name:     apb_transaction.sv
* Author:          wuqlan
* Email:           
* Date Created:    2022/12/28
* Description:     AHB req class. Random AHB req.
*
*
* Version:         0.1
*************************************************************************************/

`ifndef  AHB_SLAVE_TRANSACTION_SV
`define  AHB_SLAVE_TRANSACTION_SV

`include "definition.sv"
`include "uvm_macros.svh"

import  uvm_pkg::*;


class  ahb_slave_transaction extends uvm_transaction;

    rand bit [2:0] other_error;  
    rand bit [`AHB_DATA_WIDTH-1:0] rdata[];
    rand bit [1:0] ready;

    constraint rdata_range { rdata[`AHB_ADDR_WIDTH-1:12] == 16'h8030;}
    constraint error_ready { other_error <= (ready + 1) ;}

    `define uvm_object_utils_begin(ahb_slave_transaction)
        `uvm_field_int(other_error, UVM_ALL_ON)
        `uvm_field_array_int(rdata, UVM_ALL_ON)
        `uvm_field_int(ready, UVM_ALL_ON)
    `define uvm_object_utils_end


    function  new(string name = "ahb_slave_transaction");
        super.new(name);
    endfunction


endclass




