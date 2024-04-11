class transaction;

    rand bit newd;
    rand bit [11:0] din;
    bit cs;
    bit mosi;

    function void display (input string tag);
        $display("[%0s] DATA_NEW:%0b DIN:%0d CS:%0b MOSI:%0b", tag,newd,din,cs,mosi);
    endfunction

    function transaction copy();
        copy=new();
        copy.newd=this.newd;
        copy.din=this.din;
        copy.cs=this.cs;
        copy.mosi=this.mosi;
    endfunction

endclass

////////////////////////////

class generator;

    transaction tr;
    mailbox #(transaction) mbx;
    event done;
    event drvnext;
    event sconext;
    int count=0;

    function new(mailbox #(transaction) mbx);
        this.mbx=mbx;
        tr=new();
    endfunction

    task run();
        repeat(count) begin
            assert (tr.randomize) else $display("[GEN]: RANDOMIZATION FAILED");
            mbx.put(tr);
            tr.display("GEN");
            @(drvnext);
            @(sconext);
        end
        ->done;
    endtask

endclass

////////////////////////////

class driver;

    virtual spi_if vif;
    transaction tr;
    mailbox #(transaction) mbx;
    mailbox #(bit [11:0])mbxds;
    event drvnext;

    bit [11:0] din;

    function new(mailbox #(bit [11:0])mbxds,mailbox #(transaction) mbx);
        this.mbx=mbx;
        this.mbxds=mbxds;
    endfunction

    task reset();
        vif.rst<=1'b1;
        vif.newd<=1'b0;
        vif.din<=1'b0;
        repeat(10) @(posedge vif.clk);
        vif.rst<=1'b0;
        repeat(5) @(posedge vif.clk);

        $display("[DRV]: RESET DONE!");
        $display("------------------");
    endtask

    task run();
        forever begin
            mbx.get(tr);
            @(posedge vif.sclk);
            vif.newd<=1'b1;
            vif.din<=tr.din;
            mbxds.put(tr.din);
            @(posedge vif.sclk);
            vif.newd<=1'b0;
            wait(vif.cs==1'b1);
            $display("[DRV]: DATA SENT TO DAC: %0d", tr.din);
            ->drvnext;
        end
    endtask
endclass

////////////////////////////

class monitor;

    transaction tr;
    mailbox#(bit [11:0]) mbx;
    bit[11:0] srx; //send
    virtual spi_if vif;

    function new(mailbox#(bit [11:0]) mbx);
        this.mbx=mbx;
    endfunction

    task run();
        forever begin
            @(posedge vif.sclk);
            wait(vif.cs==1'b0); //start transaction
            @(posedge vif.sclk);

            for(int i=0;i<=11;i++) begin
                @(posedge vif.sclk);
                srx[i]=vif.mosi;
            end

            wait(vif.cs==1'b1); //end transaction
            $display("[MON]: DATA SENT: %0d", srx);
            mbx.put(srx);
        end
    endtask

endclass

////////////////////////////

class scoreboard;

    mailbox #(bit [11:0]) mbxds,mbxms;
    bit [11:0] ds;
    bit [11:0] ms;
    event sconext;

    function new(mailbox #(bit [11:0]) mbxds,mailbox #(bit [11:0]) mbxms);
        this.mbxds=mbxds;
        this.mbxms=mbxms;
    endfunction

    task run();
        forever begin
            mbxds.get(ds);
            mbxms.get(ms);
            $display("[SCO]: DRV: %0d MON: %0d", ds,ms);

            if(ds==ms) $display("[SCO]: DATA MATCHED");
            else $display("[SCO]: DATA MISMATCHED");
            
            $display("----------------------");
            ->sconext;
        end
    endtask

endclass

////////////////////////////

class environment;

    generator gen;
    driver drv;
    monitor mon;
    scoreboard sco;

    event nextgd;
    event nextgs;

    mailbox#(transaction) mbxgd; //gen->drv
    mailbox#(bit [11:0]) mbxds;  //drv->sco
    mailbox#(bit [11:0]) mbxms;  //mon->sco

    virtual spi_if vif;

    function new(virtual spi_if vif);
        mbxgd=new();
        mbxms=new();
        mbxds=new();
        gen=new(mbxgd);
        drv=new(mbxds,mbxgd);
        mon=new(mbxms);
        sco=new(mbxds,mbxms);
        this.vif=vif;
        drv.vif=this.vif;
        mon.vif=this.vif;
        gen.sconext=nextgs;
        sco.sconext=nextgs;
        gen.drvnext=nextgd;
        drv.drvnext=nextgd;
    endfunction

    task pretest();
        drv.reset();
    endtask

    task test();
        fork
            gen.run();
            drv.run();
            sco.run();
            mon.run();
        join_any
    endtask

    task post_test();
        wait(gen.done.triggered);
        $finish();
    endtask

    task run();
        pretest();
        test();
        post_test();
    endtask

endclass

////////////////////////////

module tb();

    spi_if vif();
    spi dut(vif.clk,vif.newd,vif.rst,vif.din,vif.sclk,vif.cs,vif.mosi);

    initial begin
        vif.clk<=0;
    end

    always #10 vif.clk=~vif.clk;
    environment env;

    initial begin
        env= new(vif);
        env.gen.count=20;
        env.run();
    end

    initial begin
        $dumpfile("dump.vcd");
        $dumpvars;
    end
endmodule