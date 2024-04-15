`timescale 1ns / 1ps

module i2c_master
(
    input clk,rst,newd,
    input [6:0] addr,
    input op,
    input sda,
    output scl,
    inout [7:0] din,
    output [7:0] dout,
    output reg busy,ack_err,done
);

reg scl_t=0;
reg sda_t=0;

parameter sys_freq = 40000000; //40Mhz
parameter i2c_freq= 100000; //100Khz

parameter clk_count4 = (sys_freq/i2c_freq); //400
parameter clk_count1 = clk_count/4; //100

integer  count1=0;
reg i2c_clk=0;

//4x clock
reg [1:0] pulse=0;
always @(posedge clk) begin
    if(rst) begin
        pulse<=0;
        count1<=0;
    end
    else if (busy==1'b0) begin
        pulse<=0;
        count1<=0;
    end
    else if(count1==clk_count-1) //wait till clk_count becomes 99
    begin
        pulse<=1;
        count1<=count1+1;
    end
    else if(count1==2*clk_count-1) //wait till clk_count becomes 199
    begin
        pulse<=2;
        count1<=count1+1;
    end
    else if(count1==3*clk_count-1) //wait till clk_count becomes 299
    begin
        pulse<=3;
        count1<=count1+1;
    end
     else if(count1==4*clk_count-1) //wait till clk_count becomes 399
    begin
        pulse<=0;
        count1<=0;
    end
    else count1<=count1+1;
end
//////////////////////////

reg [3:0] bitcount=0;
reg [7:0] data_addr=0, data_tx=0;
reg r_ack=0;
reg [7:0] rx_data=0;
reg sda_en=0;

typedef enum logic [3:0] {idle=0,start=1,write_addr=2,ack_1=3,write_data=4,read_data=5,stop=6,ack_2=7,master_ack=8} state_type;
state_type state=idle;

always @(posedge clk) begin
    if(rst) begin
        bitcount<=0;
        data_addr<=0;
        data_tx<=0;
        scl_t<=1;
        sda_t<=1;
        state<=idle;
        buse<=1'b0;
        ack_err<=1'b0;
        done<=1'b0;
    end
    else begin
        case (state)
            // IDLE STATE
            idle: begin
                done<=1'b0;
                if(newd==1'b1) begin
                    data_addr<={addr,op};
                    data_tx<=din;
                    busy<=1'b1;
                    state<=start;
                    ack_err<=1'b0;
                end
                else begin
                    data_addr<=0;
                    data_tx<=0;
                    busy<=1'b0;
                    state<=idle;
                    ack_err<=1'b0;
                end
            end

            // STARTE STATE
            start: begin
                sda_en<=1'b1; //send start to slave
                case (pulse)
                    0: begin scl_t<=1'b1; sda_t<=1'b1; end
                    1: begin scl_t<=1'b1; sda_t<=1'b1; end
                    2: begin scl_t<=1'b1; sda_t<=1'b0; end
                    3: begin scl_t<=1'b1; sda_t<=1'b0; end
                endcase
                if(count1==4*count1-1)//399
                begin
                    state<=write_addr;
                    scl_t<=1'b0;
                end
                else state<=start;
            end

            //WRITE ADDRESS STATE
            write_addr: begin
                sda_en<=1'b1; //send addr to slave
                if(bitcount<=7)begin
                    case (pulse)
                    0: begin scl_t<=1'b0; sda_t<=1'b0; end
                    1: begin scl_t<=1'b0; sda_t<=data_addr[7-bitcount]; end
                    2: begin scl_t<=1'b1; end
                    3: begin scl_t<=1'b1; end
                    endcase
                    if(count1==clk_count1*4-1) begin
                        state<=write_addr;
                        scl_t<=1'b0;
                        bitcount<=bitcount+1;
                    end
                    else state<=write_addr;
                end
                else begin
                    state<=ack_1;
                    bitcount<=0;
                    sda_en<=1'b0;
                end
            end

            // ACKNOWLEDGEMENT STATE
            ack_1: begin
                sda_en<=1'b0;
                case (pulse)
                    0: begin scl_t<=1'b0; sda_t<=1'b0; end
                    1: begin scl_t<=1'b0; sda_t<=1'b0; end
                    2: begin scl_t<=1'b1; sda_t<=1'b0, r_ack<=1'b0; end
                    3: begin scl_t<=1'b1; end
                endcase
                if(count1==clk_count1*4-1) begin
                    if(ack_1===1'b0 && data_addr[0]==1'b0) begin
                        state<=write_data;
                        sda_t<=1'b0;
                        sda_en<=1'b0;
                        bitcount<=0;
                    end
                    else if(ack_1===1'b0 && data_addr[0]==1'b1) begin
                        state<=read_data;
                        sda_t<=1'b1;
                        sda_en<=1'b0;
                        bitcount<=0;
                    end
                    else begin
                        state<=stop;
                        sda_en<=1'b1; //send stop to slave
                        ack_err<=1'b1;
                    end
              end
              else state<=ack_1;
            end

            // WRITE DATA
            write_data: begin
                if(bitcount<=7) begin
                    case (pulse)
                        0: begin scl_t<=1'b0; end
                        1: begin scl_t<=1'b0; sda_en<=1'b1; sda_t<=data_tx[7-bitcount]; end
                        2: begin scl_t<=1'b1; end
                        3: begin scl_t<=1'b1; end
                    endcase
                    if(count1==clk_count1*4-1) begin
                    if(ack_1===1'b0 && data_addr[0]==1'b0) begin
                        state<=write_data;
                        scl_t<=1'b0;
                        btcount<=bitcount+1;
                    end
                    else state<=write_data;
              end
                end
                else begin
                    state<=ack_2;
                    bitcount<=0;
                    sda_en<=1'b0; //read from slave
                end
            end

            // READ DATA STATE
            read_data: begin
                sda_en<=1'b0; //read data from slave
                if(bitcount<=7) begin
                    case (pulse)
                    0: begin scl_t<=1'b0; sda_t<=1'b0; end
                    1: begin scl_t<=1'b0; sda_t<=1'b0; end
                    2: begin scl_t<=1'b1; rx_data[7:0]<=(count1==200) ? {rx_data[6:0],sda}: rx_data; end
                    3: begin scl_t<=1'b1; end
                    endcase
                    if(count1  == clk_count1*4 - 1)begin
                                    state <= read_data;
                                    scl_t <= 1'b0;
                                    bitcount <= bitcount + 1;
                        end
                    else state <= read_data;
                end
                 else
                        begin
                        state <= master_ack;
                        bitcount <= 0;
                        sda_en <= 1'b1; //master will send ack to slave
                        end
            end
            
            // MASTER ACKNOWLEDGEMENT
            master_ack: begin
                sda_en<=1'b1;
                case(pulse)
                    0: begin scl_t <= 1'b0; sda_t <= 1'b1; end
                    1: begin scl_t <= 1'b0; sda_t <= 1'b1; end
                    2: begin scl_t <= 1'b1; sda_t <= 1'b1; end 
                    3: begin scl_t <= 1'b1; sda_t <= 1'b1; end
                endcase
                   
                if(count1  == clk_count1*4 - 1)begin
                    sda_t <= 1'b0;
                    state <= stop;
                    sda_en <= 1'b1; ///send stop to slave
                end
                else state <= master_ack;
            end 

            // ACKNOWLEDGEMENT 2
             ack_2: begin
                sda_en<=1'b0;
                case (pulse)
                    0: begin scl_t<=1'b0; sda_t<=1'b0; end
                    1: begin scl_t<=1'b0; sda_t<=1'b0; end
                    2: begin scl_t<=1'b1; sda_t<=1'b0, r_ack<=1'b0; end
                    3: begin scl_t<=1'b1; end
                endcase
                if(count1==clk_count1*4-1) begin
                    sda_t<=1'b0;
                    sda_en<=1'b1;   //send stop to slave
                    if(r_ack==1'b0) state<=stop;
                    else begin
                        state<=stop;
                        ack_err<=1'b1;
                    end
              end
                else state<=ack_2;
            end 

            // STOP STATE
            stop: begin
                sda_en<=1'b1; //send stop to slave
                case (pulse)
                    0: begin scl_t<=1'b1; sda_t<=1'b0; end
                    1: begin scl_t<=1'b1; sda_t<=1'b0; end
                    2: begin scl_t<=1'b1; sda_t<=1'b1; end
                    3: begin scl_t<=1'b1; sda_t<=1'b1; end
                endcase
                if(count1==4*clk_count1-1) begin
                    state<=idle;
                    scl_t<=1'b0;
                    busy<=1'b0;
                    sda_en<=1'b1; //send start to slave
                    done<=1'b1;
                end
                else state<=stop;
            end

            default: state<=idle;
        endcase
    end
end

assign sda= (sda_en==1) ? (sda_t==0) ? 1'b0: 1'b1 : 1'bz;
/*
en=1 -> write to slave else read
if sda_en==1 then if sda_t==0 pull line loew else release so that pull up make line high
*/

assign scl=scl_t;
assign dout=rx_data;

endmodule

/////////////////////////////

module i2c_slave
(
    input scl,clk,rst,
    input sda,
    output reg ack_err,done
);
endmodule