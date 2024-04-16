class transaction;

    bit newd;
    rand bit op;
    rand bit [6:0] addr;
    rand bit [6:0] din;
    bit [7:0] dout;
    bit busy,asck_err,done;

    constraint addr_c {addr >1; addr<5; din>1; din<10;}
    constraint rd_wr_c {
        op dist {1:/50, 0:/50};
    }

endclass

////////////////////////////

class generator;

    transaction tr;
    mailbox #(transaction) mbx;
    event done;
    event sconext;
    event drvnext;
    int count=0;

    function  new(mailbox #(transaction) mbx);
        this.mbx=mbx;
        tr=new();        
    endfunction

    task run();
        repeat(count) begin
            assert(tr.randomize) else $error("[GEN]: RANDOMIZATION FAILED!");
            mbx.put(tr);
            $display("[GEN] op:%0d, addr:%0d, din:%0d", tr.op,tr.addr,tr.din);
            @(drvnext);
            @(sconext);
        end
        ->done;
    endtask

endclass

////////////////////////////

class driver;

    transaction tr;
    mailbox #(transaction) mbx;
    virtual i2c_if vif;
    event drvnext;

    function new(mailbox #(transaction) mbx);
        this.mbx=mbx;        
    endfunction

    task reset();
        vif.rst<=1'b1;
        vif.newd<=1'b0;
        vif.op<=1'b0;
        vif.din<=0;
        vif.addr<=0;
        repeat(5) @(posedge vif.clk);
        vif.rst<=1'b0;
        $display("[DRV]: RESET DONE");
        $display("-----------------");
    endtask
    
    task write();
        vif.rst<=1'b0;
        vif.newd<=1'b1;
        vif.op<=1'b0;
        vif.din<=$urandom;
        vif.addr<=tr.addr;
        repeat(5) @(posedge vif.clk);
        vif.newd<=1'b0;
        @(posedge vif.done);
        $display("[DRV]: OP: WRITE, ADDR:%0d, DIN:%0d", tr.addr,tr.din);
        vif.newd<=1'b0;
    endtask

    task read();
        vif.rst<=1'b0;
        vif.newd<=1'b1;
        vif.op<=1'b1;
        vif.din<=0;
        vif.addr<=tr.addr;
        repeat (5) @(posedge vif.clk);
        vif.newd<=1'b0;
        @(posedge vif.done);
        $display("[DRV]: OP: READ, ADDR:%0d, DOUT:%0d", tr.addr,vif.dout);
    endtask

    task run();
        tr=new();
        forever begin
            mbx.get(tr);
            if(tr.op==1'b0) write();
            else read();
            ->drvnext;
        end
    endtask

endclass

////////////////////////////

class monitor;

    mailbox #(transaction) mbx;
    virtual i2c_if vif;
    transaction tr;

    function new(mailbox #(transaction) mbx);
        this.mbx=mbx;        
    endfunction

    task run();
        tr=new();
        forever begin
            @(posedge vif.done);
            tr.din=vif.din;
            tr.addr=vif.addr;
            tr.op=vif.op;
            tr.dout=vif.dout;
            repeat(5) @(posedge vif.clk);
            mbx.put(tr);
            $display("[MON]: OP:%0d, ADDR:%0d, DIN:%0d, DOUT:%0d", tr.op,tr.addr, tr.din,tr.dout);
        end 
    endtask

endclass

////////////////////////////

class scoreboard;

    transaction tr;
    mailbox #(transaction) mbx;
    event sconext;
    bit[7:0] temp;
    bit [7:0] mem[128] ='{default:0};

    function new(mailbox #(transaction) mbx);
        this.mbx=mbx;  
        for(int i=0;i<128;i++) mem[i]=i;      
    endfunction

    task run();
        forever begin
            mbx.get(tr);
            temp=mem[tr.addr];
            if(tr.op==1'b0) begin
                mem[tr.addr]=tr.din;
                $display("[SCO]: DATA STORED-> ADDR:%0d, DATA:%0d", tr.addr,tr.din);
                $display("---------------------------------------");
            end
            else begin
                if((tr.dout==temp) || (tr.dout==tr.addr)) $display("[SCO]: DATA READ-> DATA MATCHED");
                else $display("[SCO]: DATA READ-> DATA MISMATCHED");
                $display("---------------------------------------");
            end
            ->sconext;
        end
    endtask

endclass

//////////////////////

module tb;
   
  generator gen;
  driver drv;
  monitor mon;
  scoreboard sco;
  
  
  event nextgd;
  event nextgs;
 
  
  mailbox #(transaction) mbxgd, mbxms;
 
  
  i2c_if vif();
  
  i2c_top dut (vif.clk, vif.rst,  vif.newd, vif.op, vif.addr, vif.din, vif.dout, vif.busy, vif.ack_err, vif.done);
 
  initial begin
    vif.clk <= 0;
  end
  
  always #5 vif.clk <= ~vif.clk;
  
   initial begin
   
     
    mbxgd = new();
    mbxms = new();
    
    gen = new(mbxgd);
    drv = new(mbxgd);
    
    mon = new(mbxms);
    sco = new(mbxms);
 
    gen.count = 20;
  
    drv.vif = vif;
    mon.vif = vif;
    
    gen.drvnext = nextgd;
    drv.drvnext = nextgd;
    
    gen.sconext = nextgs;
    sco.sconext = nextgs;
  
   end
  
  task pre_test;
  drv.reset();
  endtask
  
  task test;
    fork
      gen.run();
      drv.run();
      mon.run();
      sco.run();
    join_any  
  endtask
  
  
  task post_test;
    wait(gen.done.triggered);
    $finish();    
  endtask
  
  task run();
    pre_test;
    test;
    post_test;
  endtask
  
  initial begin
    run();
  end
   
  initial begin
    $dumpfile("dump.vcd");
    $dumpvars();   
  end
   
endmodule