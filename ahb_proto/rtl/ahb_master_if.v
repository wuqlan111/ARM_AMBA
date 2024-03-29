
/***********************************************************************************************************
* Module Name:     ahb_master_if
* Author:          wuqlan
* Email:           
* Date Created:    2022/12/28
* Description:     AHB master interface.
*                  Address and data bus widths are configurable using AHB_ADDR_WIDTH and AHB_DATA_WIDTH parameters.
*
* Version:         0.1
************************************************************************************************************/

module ahb_master_if #(
                parameter  AHB_ADDR_WIDTH      =  32,
                parameter  AHB_DATA_WIDTH      =  32,
                parameter  AHB_WAIT_TIMEOUT    =  6
                )
(


    input  ahb_clk_in,
    input  ahb_rstn_in,

    /*-----------ahb bus signal-----------*/
    output  reg  [AHB_ADDR_WIDTH-1: 0]  ahb_addr_out,
    output  reg  [2:0]  ahb_burst_out,
    input   [AHB_DATA_WIDTH-1: 0]  ahb_rdata_in,
    input   ahb_ready_in,
    input   ahb_resp_in,
    output  reg  [2:0]  ahb_size_out,

    `ifdef  AHB_PROT
        output  reg  [ 3:0 ] ahb_prot_out,
    `endif
    `ifdef  AHB_WSTRB
        output  reg  [(AHB_DATA_WIDTH /8) -1:0]  ahb_strb_out,
    `endif

    output  reg  [1:0]  ahb_trans_out,
    output  reg  [AHB_DATA_WIDTH-1: 0] ahb_wdata_out,
    output  reg  ahb_write_out,

    /*-----------other module signal----------------*/
    input   [AHB_ADDR_WIDTH -1: 0]  other_addr_in,
    input   [2:0]  other_burst_in,
    output  other_busy_out,
    output  other_clk_out,
    input   other_delay_in,
    input   other_error_in,    
    output  reg  other_error_out,

    `ifdef  AHB_PROT
        input   [3:0]  other_prot_in,
    `endif
    `ifdef  AHB_WSTRB
        input   [(AHB_DATA_WIDTH /8) -1:0]  other_strb_in,    
    `endif

    output  reg  [AHB_DATA_WIDTH-1: 0]  other_rdata_out,
    output  reg  other_ready_out,
    input   other_sel_in,
    input   [2:0]  other_size_in,
    input   other_valid_in,    
    input   [AHB_DATA_WIDTH-1: 0]  other_wdata_in,
    input   other_write_in

);



/*master burst type*/
localparam  AHB_BURST_SINGLE   =  3'd0;
localparam  AHB_BURST_INCR     =  3'd1;
localparam  AHB_BURST_WRAP4    =  3'd2;
localparam  AHB_BURST_INCR4    =  3'd3;
localparam  AHB_BURST_WRAP8    =  3'd4;
localparam  AHB_BURST_INCR8    =  3'd5;
localparam  AHB_BURST_WRAP16   =  3'd6;
localparam  AHB_BURST_INCR16   =  3'd7;


/*master trans type*/
localparam  AHB_TRANS_IDLE    = 2'd0;
localparam  AHB_TRANS_BUSY    = 2'd1;
localparam  AHB_TRANS_NONSEQ  = 2'd2;
localparam  AHB_TRANS_SEQ     = 2'd3;



/*ahb master state*/
localparam  STATE_RST               =  3'd0;
localparam  STATE_TRANS_IDLE        =  3'd1;
localparam  STATE_TRANS_BUSY        =  3'd2;
localparam  STATE_TRANS_NONSEQ      =  3'd3;
localparam  STATE_TRANS_SEQ         =  3'd4;
localparam  STATE_ERROR             =  3'd5;



reg  [2:0]  ahb_state;
reg  [2:0]  next_state;


reg  [AHB_DATA_WIDTH -1: 0]  ahb_wdata_next;
reg  [4:0]  burst_counter;
reg  busy_2_seq;
reg  [$clog2(AHB_WAIT_TIMEOUT) -1: 0]  wait_counter;
reg  [1:0]  trans_unready;
reg  [AHB_ADDR_WIDTH -1: 0]  burst_next_addr;
reg  [AHB_ADDR_WIDTH -1: 0]  trans_addr;
reg  [2:0]  trans_len;

wire  add_new_trans;
wire  addr_aligned;
wire  addr_changed;
wire  addr_cross_bound;
wire  [AHB_ADDR_WIDTH -1: 0]  addr_next;
wire  [AHB_ADDR_WIDTH -1: 0]  addr_other_end;
wire  [7:0]  ahb_size_byte;
wire  addr_valid;
wire  burst_changed;
wire  burst_len_fixed;
wire  prot_changed;
wire  size_changed;
wire  size_valid;
wire  [ 7:0 ]  size_byte;
wire  [ 6:0 ]  size_mask;
wire  strb_changed;
wire  trans_changed;

wire  ready_timeout;
wire  wrap4_bound;
wire  wrap8_bound;
wire  wrap16_bound;


wire  cur_burst_incr;



///////////////////////////Combinational logic//////////////////////////////////////////////////

always @(*) begin
    trans_len  =  0;
    case(other_burst_in)
        AHB_BURST_SINGLE || AHB_BURST_INCR:  trans_len  =  0;
        AHB_BURST_INCR4   ||  AHB_BURST_WRAP4:   trans_len  =  2;
        AHB_BURST_INCR8   ||  AHB_BURST_WRAP8:   trans_len  =  3;
        AHB_BURST_INCR16  ||  AHB_BURST_WRAP16:  trans_len  =  4;
    endcase
end




/*get next burst addr*/
always @(*) begin

    burst_next_addr  =  0;
    if (!ahb_burst_out || !burst_counter)
        burst_next_addr  =  0;
    else if(ahb_burst_out[0])
        burst_next_addr  =  addr_next;
    else begin
        case(ahb_burst_out)
        AHB_BURST_WRAP4: burst_next_addr   =  !wrap4_bound?  addr_next: 
                                    ahb_addr_out - ( 3 << ahb_size_out );
        AHB_BURST_WRAP8: burst_next_addr   =  !wrap8_bound?  addr_next: 
                                    ahb_addr_out -  ( 7 << ahb_size_out );
        AHB_BURST_WRAP16: burst_next_addr  =  !wrap16_bound? addr_next:
                                    ahb_addr_out - ( 15 << ahb_size_out );
        default: burst_next_addr = 0;
            
        endcase
    end
    
end


/*FSM*/
always @(*) begin
    next_state =  0;
    if (!ahb_rstn_in)
        next_state      =  STATE_RST;
    else begin
        case (ahb_state)
            STATE_RST: begin
                if (!other_sel_in )
                    next_state          =    STATE_RST;
                else if (!other_valid_in)
                    next_state          =    STATE_TRANS_IDLE;
                else if ( other_error_in || !addr_valid  || !size_valid )
                    next_state          =    STATE_ERROR;
                else
                    next_state          =    STATE_TRANS_NONSEQ;
            end

            STATE_TRANS_IDLE: begin
                if (  trans_unready[1] || ( trans_unready && ( !other_sel_in || other_error_in || ready_timeout ) ) 
                       || ahb_resp_in  )
                    next_state         =     STATE_ERROR;
                else if(!other_sel_in)
                    next_state         =     STATE_RST;
                else if (  !other_valid_in )
                    next_state         =     STATE_TRANS_IDLE;
                else
                    next_state         =     STATE_TRANS_NONSEQ;

            end

            STATE_TRANS_BUSY: begin
                if ( !ahb_burst_out || (  burst_len_fixed && ( trans_changed || !other_sel_in || !other_valid_in
                        || !burst_counter ) )  || (trans_unready && ready_timeout) 
                        || other_error_in || ahb_resp_in )
                    next_state          =    STATE_ERROR;
                else  if(!other_sel_in)
                    next_state          =    STATE_RST;
                else  if (!other_valid_in)
                    next_state          =    STATE_TRANS_IDLE;
                else  if ( other_delay_in )
                    next_state          =    STATE_TRANS_BUSY;
                else  if ( burst_len_fixed || !trans_changed )
                    next_state          =    STATE_TRANS_SEQ;
                else
                    next_state          =    STATE_TRANS_NONSEQ;
            end

            STATE_TRANS_NONSEQ: begin
                if (!other_sel_in || ( !other_valid_in && burst_len_fixed) ||  other_error_in || 
                            (!ahb_burst_out && other_delay_in ) || (trans_unready && ready_timeout) )
                    next_state              =     STATE_ERROR;
                else  if (!other_valid_in)
                    next_state              =     STATE_TRANS_IDLE;
                else  if (other_delay_in)
                    next_state              =     STATE_TRANS_BUSY;
                else  if (ahb_burst_out)
                    next_state              =     STATE_TRANS_SEQ;
                else
                    next_state              =     STATE_TRANS_NONSEQ;
            end

            STATE_TRANS_SEQ: begin
                if ( !other_sel_in || !ahb_burst_out ||  other_error_in || ahb_resp_in || 
                    ( burst_counter && burst_len_fixed && ( trans_changed || !other_valid_in ) )
                    || (trans_unready && ready_timeout) || ( !burst_counter && burst_len_fixed 
                    && other_delay_in ) )
                    next_state         =     STATE_ERROR;
                else  if (!other_valid_in)
                    next_state         =     STATE_TRANS_IDLE;
                else if ( other_delay_in)
                    next_state         =     STATE_TRANS_BUSY;
                else if ( !burst_counter )
                    next_state         =     STATE_TRANS_NONSEQ;
                else
                    next_state         =    STATE_TRANS_SEQ;
                    
            end

            STATE_ERROR: begin
                
                if (trans_unready[1])
                    next_state   =   STATE_ERROR;
                else
                    next_state   =   STATE_RST;
            end

            default: next_state           =   STATE_RST;
        
        endcase
    end
end



//////////////////////////////////////Sequential logic//////////////////////////////////////////////////

/*get next state*/
always @(negedge ahb_clk_in  or negedge ahb_rstn_in) begin
    if (!ahb_rstn_in)
        ahb_state       <=   STATE_RST;
    else
        ahb_state       <=   next_state;
end


/*address control*/
always @(posedge ahb_clk_in or negedge ahb_rstn_in) begin

    if (!ahb_rstn_in) begin

        ahb_addr_out            <=   0;
        ahb_burst_out           <=   0;
        ahb_size_out            <=   0;
        ahb_trans_out           <=   0;
        ahb_write_out           <=   0;
    
        `ifdef   AHB_PROT
            ahb_prot_out            <=   0;
        `endif
        `ifdef   AHB_WSTRB
            ahb_strb_out            <=   0;
        `endif

        burst_counter           <=   0;
        busy_2_seq              <=   0;

        trans_unready           <=   0;
        wait_counter            <=   0;

        trans_addr              <=   0;
        
    end  begin
        case (ahb_state)
            STATE_RST: begin
                ahb_addr_out            <=   0;
                ahb_burst_out           <=   0;
                ahb_size_out            <=   0;
                ahb_trans_out           <=   0;
                ahb_write_out           <=   0;
            
            `ifdef   AHB_PROT
                ahb_prot_out            <=   0;
            `endif
            `ifdef   AHB_WSTRB
                ahb_strb_out            <=   0;
            `endif
                burst_counter           <=   0;
                busy_2_seq              <=   0;

                trans_unready           <=   0;
                wait_counter            <=   0;

                trans_addr              <=   0;

            end


            STATE_TRANS_IDLE: begin
                ahb_trans_out       <=   AHB_TRANS_IDLE;
                busy_2_seq          <=  0;
                
                if ( trans_unready && ahb_ready_in )begin
                    trans_unready       <=   (trans_unready - 1);
                    wait_counter        <=   trans_unready[1] ? wait_counter: 0;
                end
                else if (trans_unready)begin
                    trans_unready       <=   trans_unready;
                    wait_counter        <=   (wait_counter + 1);
                end
                else begin
                    trans_unready       <=    0;
                    wait_counter        <=    0; 
                end

            end

            STATE_TRANS_BUSY:begin
                ahb_trans_out     <=   AHB_TRANS_BUSY;
                busy_2_seq        <=   1;
                ahb_addr_out      <=   burst_next_addr;
                burst_counter     <=   cur_burst_incr? 0 :(burst_counter - 1);


                if ( trans_unready && ahb_ready_in )begin
                    trans_unready       <=   (trans_unready - 1);
                    wait_counter        <=   trans_unready[1] ? wait_counter: 0;
                end
                else if (trans_unready)begin
                    trans_unready       <=   trans_unready;
                    wait_counter        <=   (wait_counter + 1);
                end
                else begin
                    trans_unready       <=    0;
                    wait_counter        <=    0; 
                end


            end

            STATE_TRANS_NONSEQ:begin
                ahb_addr_out        <=  add_new_trans?  other_addr_in  : ahb_addr_out;
                ahb_burst_out       <=  add_new_trans?  other_burst_in  : ahb_burst_out;
                ahb_size_out        <=  add_new_trans?  other_size_in  : ahb_size_out;
                
                ahb_trans_out       <=  add_new_trans? AHB_TRANS_NONSEQ : ahb_trans_out;
                ahb_write_out       <=  add_new_trans? other_write_in  : ahb_write_out ;

                `ifdef  AHB_PROT
                    ahb_prot_out        <=  add_new_trans? other_prot_in : ahb_prot_out;
                `endif
                `ifdef  AHB_WSTRB
                    ahb_strb_out        <=  add_new_trans? other_strb_in : ahb_strb_out;
                `endif

                burst_counter       <=   add_new_trans?  ( 1<<trans_len ):  burst_counter;
                busy_2_seq          <=   0;

                trans_addr          <=   add_new_trans?  other_addr_in  : ahb_addr_out;

                if ( add_new_trans )
                    trans_unready   <=  ahb_ready_in ? trans_unready: (trans_unready + 1);                    
                else
                    trans_unready   <=  ahb_ready_in? (trans_unready -1) : trans_unready;

                if (trans_unready[1])
                    wait_counter    <=  !ahb_ready_in ?  (wait_counter+1):  wait_counter;
                else
                    wait_counter    <=  !ahb_ready_in ? wait_counter  : 0;

            end

            STATE_TRANS_SEQ:begin
                if (busy_2_seq) begin
                    busy_2_seq <= 1'd0;                    
                    ahb_addr_out       <=  ahb_addr_out;
                    burst_counter      <=  burst_counter;
                end
                else if (burst_counter  || cur_burst_incr )begin
                    ahb_addr_out    <=  trans_unready[1] && !ahb_ready_in? ahb_addr_out : burst_next_addr;
                    burst_counter   <=  cur_burst_incr || (trans_unready[1] && !ahb_ready_in) ?
                                        burst_counter :  (burst_counter -1);
                end
                else  begin
                    ahb_addr_out    <=  ahb_addr_out;                    
                    burst_counter   <=  burst_counter;
                end

                trans_unready    <=  ahb_ready_in ? trans_unready:  (trans_unready + 1);

                if (ahb_ready_in)
                    wait_counter       <=  trans_unready[1]?  wait_counter: 0;
                else
                    wait_counter       <=  trans_unready? (wait_counter + 1) :  0;

            end


            default: ;

        endcase

    end

end


/*--------data transfer--------*/
always @(posedge ahb_clk_in or negedge ahb_rstn_in) begin

    if (!ahb_rstn_in) begin
        
        ahb_wdata_next    <=   0;
        ahb_wdata_out     <=   0;
        other_ready_out   <=   0;
        other_error_out   <=   0;
        other_rdata_out   <=   0;
        
    end
    else begin
        case  (ahb_state)
            STATE_RST: begin
                ahb_wdata_next    <=   0;
                ahb_wdata_out     <=   0;
                other_ready_out   <=   0;
                other_error_out   <=   0;
                other_rdata_out   <=   0;
            end


            STATE_TRANS_IDLE: begin
                ahb_wdata_next     <=   ahb_ready_in && ahb_write_out ? other_wdata_in: ahb_wdata_next;
                ahb_wdata_out      <=   ahb_ready_in && ahb_write_out ? ahb_wdata_next:  ahb_wdata_out;
                other_ready_out    <=   trans_unready?  ahb_ready_in:  0;
                other_error_out    <=   trans_unready?  ahb_resp_in:  0;
                other_rdata_out    <=   !trans_unready || ahb_resp_in || !ahb_ready_in ? 0: ahb_rdata_in;

            end
            
            
            STATE_TRANS_BUSY || STATE_TRANS_NONSEQ || 
            STATE_TRANS_SEQ :begin
                ahb_wdata_next     <=   !trans_unready[1] || ahb_ready_in ? other_wdata_in: ahb_wdata_next;
                ahb_wdata_out      <=   !trans_unready[1] || ahb_ready_in ? ahb_wdata_next: ahb_wdata_out;
                other_ready_out    <=   ahb_ready_in;
                other_error_out    <=   ahb_resp_in;
                other_rdata_out    <=   !ahb_resp_in && ahb_ready_in? ahb_rdata_in: 0;
            end

            STATE_ERROR:begin
                ahb_wdata_next      <=   0;
                ahb_wdata_out       <=   0;
                other_ready_out     <=   1;
                other_error_out     <=   1;
                other_rdata_out     <=   0;
            end

            default:  ;
        endcase

    end

end



assign  add_new_trans  =  (other_ready_out || !trans_unready[1] ) && other_valid_in ;
assign  addr_aligned  =  ( other_addr_in & size_mask  )?  0: 1;
assign  addr_changed  = ( trans_addr != other_addr_in);
assign  addr_cross_bound  =  (addr_other_end[11:10]  != other_addr_in[11:10] );
assign  addr_other_end  =  ( other_addr_in + (size_byte << trans_len) );
assign  addr_next  =  ( ahb_addr_out + ahb_size_byte );
assign  ahb_size_byte  =  ( 1 <<  ahb_size_out);
assign  addr_valid  =  ( addr_aligned && !addr_cross_bound );
assign  burst_changed  =  ( other_burst_in  !=  ahb_burst_out);
assign  burst_len_fixed  =  (ahb_burst_out  >  AHB_BURST_INCR);

`ifdef  AHB_PROT
    assign  prot_changed  =  ( other_prot_in  != ahb_prot_out );
`else
    assign  prot_changed  =  0;
`endif
`ifdef  AHB_WSTRB
    assign  strb_changed  =  ( other_strb_in  != ahb_strb_out );
`else
    assign  strb_changed  =  0;
`endif

assign  ready_timeout  =  (wait_counter == AHB_WAIT_TIMEOUT);


assign  size_byte   =  ( 1 << other_size_in );
assign  size_changed  =  ( other_size_in  !=  ahb_size_out );
assign  size_mask   =  ( size_byte  - 1 );
assign  size_valid  =  ( size_byte  << 3 ) > AHB_DATA_WIDTH ? 0: 1;




assign  trans_changed  =  addr_changed || burst_changed || prot_changed 
                        || size_changed || strb_changed;

assign  cur_burst_incr = ( ahb_burst_out == AHB_BURST_INCR )? 1'd1: 1'd0 ;

assign  other_busy_out  =  trans_unready[1] && !ahb_ready_in ;
assign  other_clk_out =  ahb_clk_in;

assign   wrap4_bound   =  ( addr_next & ( ( ahb_size_byte << 2) - 1))?  0:  1;
assign   wrap8_bound   =  ( addr_next & ( ( ahb_size_byte << 3) - 1))?  0:  1;
assign   wrap16_bound  =  ( addr_next & ( ( ahb_size_byte << 4) - 1))?  0:  1;


endmodule

