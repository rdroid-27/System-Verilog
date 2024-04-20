interface axi_if;

    ////////write address channel (aw)
    logic awvalid;  /// master is sending new address  
    logic awready;  /// slave is ready to accept request
    logic [3:0] awid; ////// unique ID for each transaction
    logic [3:0] awlen; ////// burst length AXI3 : 1 to 16, AXI4 : 1 to 256
    logic [2:0] awsize; ////unique transaction size : 1,2,4,8,16 ...128 bytes
    logic [31:0] awaddr; ////write adress of transaction
    logic [1:0] awburst; ////burst type : fixed , INCR , WRAP
    
    
    //////////write data channel (w)
    logic wvalid; //// master is sending new data
    logic wready; //// slave is ready to accept new data 
    logic [3:0] wid; /// unique id for transaction
    logic [31:0] wdata; //// data 
    logic [3:0] wstrb; //// lane having valid data
    logic wlast; //// last transfer in write burst
    
    
    //////////write response channel (b) 
    logic bready; ///master is ready to accept response
    logic bvalid; //// slave has valid response
    logic [3:0] bid; ////unique id for transaction
    logic [1:0] bresp; /// status of write transaction 
    
    ///////////////read address channel (ar)
    logic arvalid;  /// master is sending new address  
    logic arready;  /// slave is ready to accept request
    logic [3:0] arid; ////// unique ID for each transaction
    logic [3:0] arlen; ////// burst length AXI3 : 1 to 16, AXI4 : 1 to 256
    logic [2:0] arsize; ////unique transaction size : 1,2,4,8,16 ...128 bytes
    logic [31:0] araddr; ////write adress of transaction
    logic [1:0] arburst; ////burst type : fixed , INCR , WRAP
    
    /////////// read data channel (r)
    logic rvalid; //// master is sending new data
    logic rready; //// slave is ready to accept new data 
    logic [3:0] rid; /// unique id for transaction
    logic [31:0] rdata; //// data 
    logic [3:0] rstrb; //// lane having valid data
    logic rlast; //// last transfer in write burst
    logic [1:0] rresp; ///status of read transfer
    
    ////////////////
    logic clk;
    logic resetn;
    
    //////////////////
    logic [31:0] addr_wrapwr;
    logic [31:0] addr_wraprd;
  
endinterface //axi_if   

///////////////////////////////////////////////////////////////////////

module axi_slave(

    //global control signals
    input clk,
    input resetn,
    
    //write address channel
    input  awvalid,  /// master is sending new address  
    output reg awready,  /// slave is ready to accept request
    input [3:0] awid, ////// unique ID for each transaction
    input [3:0] awlen, ////// burst length AXI3 : 1 to 16, AXI4 : 1 to 256
    input [2:0] awsize, ////unique transaction size : 1,2,4,8,16 ...128 bytes
    input [31:0] awaddr, ////write adress of transaction
    input [1:0] awburst, ////burst type : fixed , INCR , WRAP
    
    //write data channel
    input wvalid, //// master is sending new data
    output reg wready, //// slave is ready to accept new data 
    input [3:0] wid, /// unique id for transaction
    input [31:0] wdata, //// data 
    input [3:0] wstrb, //// lane having valid data
    input wlast, //// last transfer in write burst
    
    //write response channel
    input bready, ///master is ready to accept response
    output reg bvalid, //// slave has valid response
    output reg [3:0] bid, ////unique id for transaction
    output reg [1:0] bresp, /// status of write transaction 
    
    //read address channel
    output reg	arready,  //read address ready signal from slave
    input [3:0] arid,      //read address id
    input [31:0] araddr,		//read address signal
    input [3:0] arlen,      //length of the burst
    input [2:0] arsize,		//number of bytes in a transfer
    input [1:0] arburst,	//burst type - fixed, incremental, wrapping
    input arvalid,	//address read valid signal
        
    //read data channel
    output reg [3:0] rid,	//read data id
    output reg [31:0] rdata,//read data from slave
    output reg [1:0] rresp,	//read response signal
    output reg rlast,		//read data last signal
    output reg rvalid,		//read data valid signal
    input rready
);

    typedef enum bit [1:0] { awidle=2'b00, awstart=2'b01, awreadys=2'b10 } awstate_type;
    awstate_type awstate, awnext_state;
    typedef enum bit [1:0] { wilde=2'b00, wstart=2'b01, wreadys=2'b10 } wstate_type;
    wstate_type wstate, wnext_state;
    typedef enum bit [1:0] { bilde=2'b00, bstart=2'b01, breadys=2'b10 } bstate_type;
    bstate_type bstate, bnext_state;
    
    reg [31:0] awaddrt;
    
    // reset decoder
    always_ff @(posedge clk,negedge resetn) begin
        if(!resetn) begin
            awstate<=awidle;
            wstate<=wilde;
            bstate<=bilde;
        end
        else begin
            awstate<=awnext_state;
            wstate<=wnext_state;
            bstate<=bnext_state;
        end
    end

    // FSM for write address channel
    always_comb begin
        case(awstate)
        
            awidle:begin
                awready=1'b0;
                awnext_state=awstart;
            end

            awstart: begin
                if(awvalid) begin
                    awnext_state=awreadys;
                    awaddrt=awaddr; //storing address
                end
                else awnext_state=awstart;
            end

            awreadys: begin
                awready=1'b1;
                awnext_state=awidle; 
            end    

        endcase
    end

    // FSM for Write Data Channel
    reg [31:0] wdatat;
    reg [7:0] mem [128]='{default:12};
    reg [31:0] retaddr;
    reg [31:0] nextaddr;
    reg first; //check operation executrd first time

        // function to compute next address during fixed burst type
        function bit[31:0] data_wr_fixed(input bit[3:0] wstrb,input bit[31:0] awaddrt);
            unique case (wstrb)                     
                4'b0001: begin
                    men[awaddrt]=wdatat[7:0];
                end 
                4'b0010: begin
                    mem[awaddrt]=wdatat[15:8];
                end
                4'b0011:begin
                    mem[awaddrt]=wdatat[7:0];
                    mem[awaddrt+1]=wdatat[15:8];
                end
                4'b0100:begin
                    mem[awaddrt]=wdatat[23:16];
                end
                4'b0101:begin
                    mem[awaddrt]=wdatat[7:0];
                    mem[awaddrt+1]=wdatat[23:16];
                end
                4'b0110:begin
                    mem[awaddrt]=wdatat[15:8];
                    mem[awaddrt+1]=wdatat[23:16];
                end
                4'b0111:begin
                    mem[awaddrt]=wdatat[7:0];
                    mem[awaddrt+1]=wdatat[15:8];
                    mem[awaddrt+2]=wdatat[23:16];
                end
                4'b1000:begin
                    mem[awaddrt]=wdatat[31:24];
                end
                4'b1001:begin
                    mem[awaddrt]=wdatat[7:0];
                    mem[awaddrt+1]=wdatat[31:24];
                end
                4'b1010:begin
                    mem[awaddrt]=wdatat[15:8];
                    mem[awaddrt+1]=wdatat[31:24];
                end
                4'b1011:begin
                    mem[awaddrt]=wdatat[7:0];
                    mem[awaddrt+1]=wdatat[15:8];
                    mem[awaddrt+2]=wdatat[31:24];
                end
                4'b1100:begin
                    mem[awaddrt]=wdatat[23:16];
                    mem[awaddrt+1]=wdatat[31:24];
                end
                4'b1101:begin
                    mem[awaddrt]=wdatat[7:0];
                    mem[awaddrt+1]=wdatat[23:16];
                    mem[awaddrt+2]=wdatat[31:24];
                end
                4'b1110:begin
                    mem[awaddrt]=wdatat[15:8];
                    mem[awaddrt+1]=wdatat[23:16];
                    mem[awaddrt+2]=wdatat[31:24];
                end
                4'b1111:begin
                    mem[awaddrt]=wdatat[7:0];
                    mem[awaddrt+1]=wdatat[15:8];
                    mem[awaddrt+2]=wdatat[23:16];
                    mem[awaddrt+3]=wdatat[31:24];
                end 
            endcase          
            return awaddrt;    
        endfunction

        // function to compute next address during incr burst type
        function bit[31:0] data_wr_incr(input bit[3:0] wstrb,input bit[31:0] awaddrt);
            bit [31:0] addr;
            unique case (wstrb)                     
                4'b0001: begin
                    men[awaddrt]=wdatat[7:0];
                    addr=awaddrt+1;
                end 
                4'b0010: begin
                    mem[awaddrt]=wdatat[15:8];
                    addr=awaddrt+1;
                end
                4'b0011:begin
                    mem[awaddrt]=wdatat[7:0];
                    mem[awaddrt+1]=wdatat[15:8];
                    addr=awaddrt+2;
                end
                4'b0100:begin
                    mem[awaddrt]=wdatat[23:16];
                    addr=awaddrt+1;
                end
                4'b0101:begin
                    mem[awaddrt]=wdatat[7:0];
                    mem[awaddrt+1]=wdatat[23:16];
                    addr=awaddrt+2;
                end
                4'b0110:begin
                    mem[awaddrt]=wdatat[15:8];
                    mem[awaddrt+1]=wdatat[23:16];
                    addr=awaddrt+2;
                end
                4'b0111:begin
                    mem[awaddrt]=wdatat[7:0];
                    mem[awaddrt+1]=wdatat[15:8];
                    mem[awaddrt+2]=wdatat[23:16];
                    addr=awaddrt+3;
                end
                4'b1000:begin
                    mem[awaddrt]=wdatat[31:24];
                    addr=awaddrt+1;
                end
                4'b1001:begin
                    mem[awaddrt]=wdatat[7:0];
                    mem[awaddrt+1]=wdatat[31:24];
                    addr=awaddrt+2;
                end
                4'b1010:begin
                    mem[awaddrt]=wdatat[15:8];
                    mem[awaddrt+1]=wdatat[31:24];
                    addr=awaddrt+2;
                end
                4'b1011:begin
                    mem[awaddrt]=wdatat[7:0];
                    mem[awaddrt+1]=wdatat[15:8];
                    mem[awaddrt+2]=wdatat[31:24];
                    addr=awaddrt+3;
                end
                4'b1100:begin
                    mem[awaddrt]=wdatat[23:16];
                    mem[awaddrt+1]=wdatat[31:24];
                    addr=awaddrt+2;
                end
                4'b1101:begin
                    mem[awaddrt]=wdatat[7:0];
                    mem[awaddrt+1]=wdatat[23:16];
                    mem[awaddrt+2]=wdatat[31:24];
                    addr=awaddrt+3;
                end
                4'b1110:begin
                    mem[awaddrt]=wdatat[15:8];
                    mem[awaddrt+1]=wdatat[23:16];
                    mem[awaddrt+2]=wdatat[31:24];
                    addr=awaddrt+3;
                end
                4'b1111:begin
                    mem[awaddrt]=wdatat[7:0];
                    mem[awaddrt+1]=wdatat[15:8];
                    mem[awaddrt+2]=wdatat[23:16];
                    mem[awaddrt+3]=wdatat[31:24];
                    addr=awaddrt+4;
                end 
            endcase          
            return addr;    
        endfunction

        // function to compute wrapping boundary
        function bit[7:0] wrap_boundary(input bit[3:0] awlen,input bit[2:0] awsize);
            bit [7:0] boundary;

            unique case (awlen)                     
              4'b0001: begin
                unique case(awsize)
                3'b000: boundary=2*1;
                3'b001: boundary=2*2;
                3'b010: boundary=2*4;
                endcase
              end
              4'b0011: begin
                unique case(awsize)
                3'b000: boundary=4*1;
                3'b001: boundary=4*2;
                3'b010: boundary=4*4;
                endcase
              end
              4'b0111: begin
                unique case(awsize)
                3'b000: boundary=8*1;
                3'b001: boundary=8*2;
                3'b010: boundary=8*4;
                endcase
              end
              4'b1111: begin
                unique case(awsize)
                3'b000: boundary=16*1;
                3'b001: boundary=16*2;
                3'b010: boundary=16*4;
                endcase
              end
            endcase          
            return boundary;    
        endfunction

        // function to compute next address during wrap butst type
        function bit[7:0] data_wr_wrap(input [3:0] wstrb, input [31:0] awaddrt, input [7:0] wboundary);
            bit [31:0] addr1, addr2, addr3, addr4;
            bit [31:0] nextaddr,nextaddr2;

            unique case (wstrb)
                    4'b0001: begin 
                mem[awaddrt] = wdatat[7:0];
                
                if((awaddrt + 1) % wboundary == 0)
                addr1 = (awaddrt + 1) - wboundary;
                else
                addr1 = awaddrt + 1;
                
            return addr1;      
            end
            
            /////////////////////////////////////////////////
            
            4'b0010: begin 
                mem[awaddrt] = wdatat[15:8];
                
            if((awaddrt + 1) % wboundary == 0)
                addr1 = (awaddrt + 1) - wboundary;
                else
                addr1 = awaddrt + 1;
                
            return addr1;   
            end
            
            ///////////////////////////////////////////////////
            
            4'b0011: begin 
                mem[awaddrt] = wdatat[7:0];
                
            if((awaddrt + 1) % wboundary == 0)
                addr1 = (awaddrt + 1) - wboundary;
                else
                addr1 = awaddrt + 1;
                        
            mem[addr1] = wdatat[15:8]; 
                    
            if((addr1 + 1) % wboundary == 0)
                addr2 = (addr1 + 1) - wboundary;
                else
                addr2 = addr1 + 1;
                
                return addr2;   
                
            end
                
            ///////////////////////////////////////////////  
            
            4'b0100: begin 
                mem[awaddrt] = wdatat[23:16];
                
                if((awaddrt + 1) % wboundary == 0)
                addr1 = (awaddrt + 1) - wboundary;
                else
                addr1 = awaddrt + 1;
                
            return addr1;
            end
            
            //////////////////////////////////////////////
            
            4'b0101: begin 
                mem[awaddrt] = wdatat[7:0];
                
                if((awaddrt + 1) % wboundary == 0)
                addr1 = (awaddrt + 1) - wboundary;
                else
                addr1 = awaddrt + 1;
                
                
                mem[addr1] = wdatat[23:16];
                
                
                if((addr1 + 1) % wboundary == 0)
                addr2 = (addr1 + 1) - wboundary;
                else
                addr2 = addr1 + 1;
                
                return addr2;  
                    
            end
            
            ///////////////////////////////////////////////////
            
            4'b0110: begin 
                mem[awaddrt] = wdatat[15:8];
                
                if((awaddrt + 1) % wboundary == 0)
                addr1 = (awaddrt + 1) - wboundary;
                else
                addr1 = awaddrt + 1;
                
                mem[addr1] = wdatat[23:16];
                
                if((addr1 + 1) % wboundary == 0)
                addr2 = (addr1 + 1) - wboundary;
                else
                addr2 = addr1 + 1;
                
                return addr2;  
                
            end
            //////////////////////////////////////////////////////////////
            
            4'b0111: begin 
                mem[awaddrt] = wdatat[7:0];    
                if((awaddrt + 1) % wboundary == 0)
                addr1 = (awaddrt + 1) - wboundary;
                else
                addr1 = awaddrt + 1;
                
                mem[addr1] = wdatat[15:8];
                
                if((addr1 + 1) % wboundary == 0)
                addr2 = (addr1 + 1) - wboundary;
                else
                addr2 = addr1 + 1;
                
                mem[addr2] = wdatat[23:16];
                
                if((addr2 + 1) % wboundary == 0)
                addr3 = (addr2 + 1) - wboundary;
                else
                addr3 = addr2 + 1;
                
                return addr3;
            end
            
            4'b1000: begin 
                mem[awaddrt] = wdatat[31:24];
                
                if((awaddrt + 1) % wboundary == 0)
                addr1 = (awaddrt + 1) - wboundary;
                else
                addr1 = awaddrt + 1;
                
                return addr1;
            end
            
            4'b1001: begin 
                mem[awaddrt] = wdatat[7:0];
                
                if((awaddrt + 1) % wboundary == 0)
                addr1 = (awaddrt + 1) - wboundary;
                else
                addr1 = awaddrt + 1;
                
                
                mem[addr1] = wdatat[31:24];
                
                if((addr1 + 1) % wboundary == 0)
                addr2 = (addr1 + 1) - wboundary;
                else
                addr2 = addr1 + 1;
                
                return addr2;
            end
            
            
            4'b1010: begin 
                mem[awaddrt] = wdatat[15:8];
                
                if((awaddrt + 1) % wboundary == 0)
                addr1 = (awaddrt + 1) - wboundary;
                else
                addr1 = awaddrt + 1;
                
                mem[addr1] = wdatat[31:24];
                
                if((addr1 + 1) % wboundary == 0)
                addr2 = (addr1 + 1) - wboundary;
                else
                addr2 = addr1 + 1;
                
                return addr2;
            end
            
            
            4'b1011: begin 
                mem[awaddrt] = wdatat[7:0];
                
                if((awaddrt + 1) % wboundary == 0)
                addr1 = (awaddrt + 1) - wboundary;
                else
                addr1 = awaddrt + 1;
                
                
                mem[addr1] = wdatat[15:8];
                
                if((addr1 + 1) % wboundary == 0)
                addr2 = (addr1 + 1) - wboundary;
                else
                addr2 = addr1 + 1;
                
                mem[addr2] = wdatat[31:24];
                
                if((addr2 + 1) % wboundary == 0)
                addr3 = (addr2 + 1) - wboundary;
                else
                addr3 = addr2 + 1;
                            
            return addr3;
            
            end
            
            4'b1100: begin 
                mem[awaddrt] = wdatat[23:16];
                
                if((awaddrt + 1) % wboundary == 0)
                addr1 = (awaddrt + 1) - wboundary;
                else
                addr1 = awaddrt + 1;
                
                mem[addr1] = wdatat[31:24];
                
                if((addr1 + 1) % wboundary == 0)
                addr2 = (addr1 + 1) - wboundary;
                else
                addr2 = addr1 + 1;
                
                return addr2;
            end
        
            4'b1101: begin 
                mem[awaddrt] = wdatat[7:0];
                
                if((awaddrt + 1) % wboundary == 0)
                addr1 = (awaddrt + 1) - wboundary;
                else
                addr1 = awaddrt + 1;
                
                mem[addr1] = wdatat[23:16];
                
                if((addr1 + 1) % wboundary == 0)
                addr2 = (addr1 + 1) - wboundary;
                else
                addr2 = addr1 + 1;
                
                mem[addr2] = wdatat[31:24];
                
                if((addr2 + 1) % wboundary == 0)
                addr3 = (addr2 + 1) - wboundary;
                else
                addr3 = addr2 + 1;
                            
            return addr3;
                
            end
        
            4'b1110: begin 
                mem[awaddrt] = wdatat[15:8];
                
                if((awaddrt + 1) % wboundary == 0)
                addr1 = (awaddrt + 1) - wboundary;
                else
                addr1 = awaddrt + 1;
                
                mem[addr1] = wdatat[23:16];
                
                if((addr1 + 1) % wboundary == 0)
                addr2 = (addr1 + 1) - wboundary;
                else
                addr2 = addr1 + 1;
                
                mem[addr2] = wdatat[31:24];
                
                if((addr2 + 1) % wboundary == 0)
                addr3 = (addr2 + 1) - wboundary;
                else
                addr3 = addr2 + 1;
                
                return addr3;
            end
            
            4'b1111: begin
                mem[awaddrt] = wdatat[7:0];
                
                if((awaddrt + 1) % wboundary == 0)
                addr1 = (awaddrt + 1) - wboundary;
                else
                addr1 = awaddrt + 1;
                
                mem[addr1] = wdatat[15:8];
                
                if((addr1 + 1) % wboundary == 0)
                addr2 = (addr1 + 1) - wboundary;
                else
                addr2 = addr1 + 1;
                
                mem[addr2] = wdatat[23:16];
                
                if((addr2 + 1) % wboundary == 0)
                addr3 = (addr2 + 1) - wboundary;
                else
                addr3 = addr2 + 1;
                
                
                mem[addr3] = wdatat[31:24]; 
                
            if((addr3 + 1) % wboundary == 0)
                addr4 = (addr3 + 1) - wboundary;
                else
                addr4 = addr3 + 1;
                
                return addr4;        
            end
        endcase
        endfunction

        // fsm for write data
        reg [7:0] boundary; //storing boundary
        reg [3:0] wlen_count;

        typedef enum bit [2:0] { widle=0, wstart=1, wreadys=2, wvalids=3, waddr_dec=4 } wstate_type;
        wstate_type wstate,wnext_state;

        always_comb
        begin
            case (wstate)
                widle: begin
                    wready=1'b0;
                    wnext_state=wstart;
                    first=1'b0;
                    wlen_count=0;
                end 
                
                wstart: begin
                    if(wvalid) begin
                        wnext_state=waddr_dec;
                        wdatat=wdata;
                    end
                    else wnext_state=wstart;
                end 

                waddr_dec:begin
                    wnext_state=wreadys;
                    if(first==0) begin
                        nextaddr=awaddr;
                        first=1'b1;
                    end
                    else if(wlen_count!=(awlen+1)) nextaddr=retaddr;
                    else nextaddr=awaddr;
                end

                wreadys: begin
                    if(wlast==1'b1) begin
                        wnext_state=widle;
                        wready=1'b0;
                        wlen_count=0;
                        first=0;
                    end
                    else begin
                        wnext_state=wvalids;
                        wready=1'b1;
                    end

                    case (awburst)
                        2'b00: retaddr=data_wr_fixed(wstrb,awaddr);
                        2'b01: retaddr=data_wr_incr(wstrb,awaddr);
                        2'b10: begin
                            boundary=wrap_boundary(awlen,awsize);
                            retaddr=data_wr_wrap(wstrb,nextaddr,boundary);
                        end 
                    endcase
                end

                wvalids: begin
                    wready=1'b0;
                    wnext_state=wstart;
                    if(wlen_count!=(awlen+1)) wlen_count=wlen_count+1;
                    else wlen_count=wlen_count;
                end
            endcase
        end
        
        // fsm for write response

endmodule