class transaction;

    rand bit t;
    bit tout;
    rand bit q;

    function transaction copy();
        copy=new();
        copy.t=this.t;
        copy.tout=this.tout;
        copy.q=this.q;
    endfunction

endclass

////////////////////////////////

class generator;

    transaction tr;
    mailbox #(transaction) mbx;
    mailbox #(transaction) mbxgs;
    event sconext;
    event done;
    int count;

    function new(mailbox #(transaction) mbx,
                 mailbox #(transaction) mbxgs);
        this.mbx=mbx;
        this.mbxgs=mbxgs;
        tr=new();
    endfunction

    task run();
        repeat(count) begin
            assert (tr.randomize) else $error("[GEN]: RANDOMIZATION ERROR!");
            mbx.put(tr.copy);
            mbxgs.put(tr.copy);
            @(sconext);
        end
        ->done;
    endtask

endclass

////////////////////////////////

class driver;

    virtual tff_if vif;
    transaction tr;
    mailbox #(transaction)mbx;
    event drvnext;
    function new(mailbox #(transaction)mbx);
        this.mbx=mbx;
    endfunction

    task reset();
    vif.rst<=1'b1;
    vif.tout<=1'b0;
    repeat(5) @(posedge vif.clk);
    vif.rst<=1'b0;
    @(posedge vif.clk);
    $display("[DRV]: RESET DONE!");
    endtask

    task run();
        forever begin
            mbx.get(tr);
            vif.t<=tr.t;
            vif.q<=tr.q;
            @(posedge vif.clk);
            $display("[DRV]: DATA SENT t: %0d Q: %0d",vif.t,vif.q);
            vif.t<=1'b0;
            @(posedge vif.clk);
        end
    endtask

endclass

////////////////////////////////

class monitor;

    virtual tff_if vif;
    transaction tr;
    mailbox #(transaction) mbx;

    function new(mailbox #(transaction) mbx);
        this.mbx=mbx;
    endfunction

    task run();
        tr=new();
        forever begin
            repeat(2) @(posedge vif.clk);
            tr.tout=vif.tout;
            mbx.put(tr);
            $display("[MON]: DATA RECIEVED Tout: %0d", tr.tout);       
        end

    endtask

endclass

////////////////////////////////

class scoreboard;

    transaction tr;
    transaction trgs;
    mailbox #(transaction) mbx;
    mailbox #(transaction) mbxgs;
    event sconext;

    function new(mailbox #(transaction) mbx,
                 mailbox #(transaction) mbxgs);
                 this.mbx=mbx;
                 this.mbxgs=mbxgs;
                 tr=new();
    endfunction

    task run();
        forever begin
            mbx.get(tr);
            mbxgs.get(trgs);
            if(trgs.t==1'b1) begin
                if(trgs.q==(~tr.tout)) $display("[SCO]: DATA MATCHED");
                else $display("[SCO]: DATA MISMATCHED");
            end
            else begin
                if(trgs.q==tr.tout)$display("[SCO]: DATA MATCHED");
                else $display("[SCO]: DATA MISMATCHED");
            end
            $display("---------------------------");
            ->sconext;
        end
    endtask
endclass

////////////////////////////////

class environment;

    virtual tff_if vif;
    generator gen;
    driver drv;
    monitor mon;
    scoreboard sco;
    event nextgd;
    event nextgs;
    mailbox #(transaction) mbxgd;
    mailbox #(transaction) mbxgs;
    mailbox #(transaction) mbxms;

    function new(virtual tff_if vif);
        mbxgd=new();
        mbxgs=new();
        mbxms=new();

        gen=new(mbxgd,mbxgs);
        drv=new(mbxgd);
        mon=new(mbxms);
        sco=new(mbxms,mbxgs);
        this.vif=vif;
        drv.vif=this.vif;
        mon.vif=this.vif;
        gen.sconext=nextgs;
        sco.sconext=nextgs;
    endfunction

    task pre_test();
        drv.reset();
    endtask

    task test();
        fork 
            gen.run();
            drv.run();
            mon.run();
            sco.run();
        join_any
    endtask

    task post_test();
        wait(gen.done.triggered);
        $finish();
    endtask

    task run();
        pre_test();
        test();
        post_test();
    endtask

endclass

////////////////////////////////

module tb();

    tff_if vif();
    tff dut (vif);

    initial begin
        vif.clk<=0;
    end

    always #10 vif.clk<=~vif.clk;
    environment env;

    initial begin
        env=new(vif);
        env.gen.count=5;
        env.run();
    end

    initial begin
        $dumpfile("dump.vcd");
        $dumpvars;
    end

endmodule