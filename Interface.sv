interface my_interface #(parameter int DATA_WIDTH = 8) (input logic clk); 

  logic reset_n; 
  logic req; 
  logic ack; 
  logic [DATA_WIDTH-1:0] data;
  bit assertions_en = 1; 

  // --- Clocking Blocks ---
  clocking drv_cb @(posedge clk);
    default input #1ns output #1ns; 
    output req;
    output data;
    input  ack;
  endclocking

  clocking mon_cb @(posedge clk);
    default input #1ns;
    input req;
    input data;
    input ack;
  endclocking

  // --- Modports ---
  modport DRIVER_MP  (clocking drv_cb, input reset_n);
  modport MONITOR_MP (clocking mon_cb, input reset_n);

  // --- Functional Coverage (Timing & Protocol) ---
  covergroup cg_handshake_timing @(mon_cb);
    option.per_instance = 1;
    option.name = "Protocol_Timing_Coverage";

    cp_ack_latency: coverpoint ($countones(req && !ack)) {
        bins immediate = {0};      
        bins fast      = {1};      
        bins medium    = {[2:5]};   
        bins slow      = {[6:20]};  
        bins timeout   = {21};     
    }

    cp_idle_between_req: coverpoint ($countones(!req && !ack)) {
        bins back_to_back = {0};    
        bins short_idle   = {1};
        bins long_idle    = {[2:50]};
    }
  endgroup

  cg_handshake_timing cg_inst = new();  
  cover_data_stability: cover property (p_data_stability);
  cover_req_ack_handshake: cover property (req ##[1:5] ack); // וידוא שהיה handshake מהיר

  // --- Properties (SVA) ---
  
  property p_data_stability;
    @(mon_cb) disable iff (!reset_n || !assertions_en)
    (mon_cb.req && !mon_cb.ack) |=> $stable(data) throughout (ack [->1]);
  endproperty 

  property p_no_spurious_ack;
    @(mon_cb) disable iff (!reset_n || !assertions_en)
    $rose(mon_cb.ack) -> req;
  endproperty

  property p_req_persistence; 
    @(mon_cb) disable iff (!reset_n || !assertions_en)
    (mon_cb.req && !mon_cb.ack) |=> req until_with ack;
  endproperty

  // --- Assertion Directives ---

  assert_data_stability: assert property (p_data_stability) 
    else $error("[SVA ERROR] DATA toggled while waiting for ACK");
               
  assert_act_valid: assert property (p_no_spurious_ack)
    else $error("[SVA ERROR] ACK rose without a valid REQ!");

  assert_req_persistence: assert property (p_req_persistence)
    else $error("[SVA ERROR] REQ dropped before ACK was received!");

endinterface
