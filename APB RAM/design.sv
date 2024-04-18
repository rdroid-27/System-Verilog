module apb_ram(
    input presetn,
    input pclk,
    input [31:0]paddr,
    input [31:0] pwdata,
    input psel,
    input penable,
    input pwrite,
    output reg pready, pslverr,
    output reg [31:0] prdata
);

reg [31:0] mem [32];

typedef enum {idle=0, setup=1, access=2, transfer=3} state_type;
state_type state=idle;

always @(posedge pclk) begin
    // RESET CONDITION
    if(presetn == 1'b0)//active low
    begin
    state<=idle;
    prdata<=32'h00000000;
    pready<=1'b0;
    pslverr<=1'b0;
    for(int i=0;i<32;i++) mem[i]<=0;
    end
    else begin
        case (state)
            //IDLE STATE
            idle: begin
                prdata<=32'h00000000;
                pready<=1'b0;
                pslverr<=1'b0;
                if((psel==1'b0) && (penable==1'b0)) state<=setup;
            end

            // SETUP STATE
            setup: begin
                if((psel==1'b1) && (penable==1'b0)) begin
                    if(paddr<32) begin
                        state<=access;
                        pready<=1'b1;
                    end
                    else begin
                        state<=access;
                        pready<=1'b0;
                    end
                end
                else state<=setup;
            end

            // ACCESS STATE
            access: begin
                if(psel==1'b1 && penable==1'b1 && pwrite==1'b1) begin
                    if(paddr<32) begin 
                    mem[paddr]<=pwdata;
                    state<=transfer;
                    pslverr<=1'b0;
                    end
                    else begin
                        state<=transfer;
                        pready<=1'b1;
                        pslverr<=1'b1;
                    end
                end
                else if(psel==1'b1 && penable==1'b1 && pwrite==1'b0) begin
                    if(paddr<32) begin
                        prdata<=mem[paddr];
                        state<=transfer;
                        pready<=1'b1;
                        pslverr<=1'b0;
                    end
                    else begin
                        state<=transfer;
                        pready<=1'b1;
                        pslverr<=1'b1;
                        prdata<=32'hxxxxxxxx;
                    end
                end
            end
                // TRANSFER STATE
            transfer: begin
                state<=setup;
                pready<=1'b0;
                pslverr<=1'b0;
            end
            
            default: state<=idle;
        endcase
    end
end

endmodule

//////////////////////

interface apb_if;
    logic presetn;
    logic pclk;
    logic [31:0]paddr;
    logic [31:0] pwdata;
    logic psel;
    logic penable;
    logic pwrite;
    logic pready, pslverr;
    logic [31:0] prdata;
endinterface