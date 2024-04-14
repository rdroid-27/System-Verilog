module tff(tff_if vif);
always @(posedge vif.clk) begin
    if(vif.rst==1'b1) begin
        vif.tout<=1'b0;
        vif.q<=1'b0;
    end
    else begin
    if(vif.t==1'b0) vif.tout<=vif.q;
    else begin
        vif.tout<=~vif.q;
        vif.q<=~vif.q;
    end
    end
end
endmodule

/////////////////

interface tff_if;
    logic clk;
    logic rst;
    logic t;
    logic q;
    logic tout;
endinterface