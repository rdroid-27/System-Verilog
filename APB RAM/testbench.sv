class transaction;

    typedef enum int { write=0, read=1, random=2, error=3 } op_type;

    randc op_type oper;
    rand bit[31:0] paddr;
    rand bit [31:0] pwdata;
    rand bit psel;
    rand bit penable;
    rand bit pwrite;
    bit [31:0] prdata;
    bit pready;
    bit pslverr;

    constraint addr_c{ paddr>1; paddr<5;}
    constraint data_c{pwdata>1; pwdata<10;}
  
    function void display(input string tag);
        $display("[%s]: OP:%0s, PADDR:%0d, PWDATA:%0d, PSEL:%0d, PENABLE:%0d, PWRITE:%0d, PREADY:%0d, PSLVERR:%0d",tag,oper.name(),paddr,pwdata,psel,penable,pwrite,pready,pslverr);
    endfunction

    function transaction copy();
        copy=new();
        copy.oper=this.oper;        
        copy.paddr=this.paddr;        
        copy.pwdata=this.pwdata;        
        copy.psel=this.psel;        
        copy.penable=this.penable;        
        copy.pwrite=this.pwrite;        
        copy.pready=this.pready;        
        copy.prdata=this.prdata;        
        copy.pslverr=this.pslverr;        
    endfunction

endclass

//////////////////////////////////

class generator;

    transaction tr;
    mailbox #(transaction) mbx;
    int count=0;
    event done;
    event drvnext;
    event sconext;

    function new(mailbox #(transaction) mbx);
        this.mbx=mbx;
        tr=new();
    endfunction

    task run();
        repeat(count) begin
            assert (tr.randomize()) else $error("[GEN]: RANDOMIZATION FAILED"); 
            mbx.put(tr.copy);
            tr.display("GEN");
            @(drvnext);
            @(sconext);
            $display("--------------------------------");
        end
        ->done;
    endtask

endclass

/////////////////////////////////

class driver;

    transaction tr;
    virtual apb_if vif;
    mailbox #(transaction) mbx;
    event drvnext;

    function new(mailbox #(transaction) mbx);
        this.mbx=mbx;
    endfunction

    task reset();
        vif.presetn<=1'b0;
        vif.psel<=1'b0;
        vif.penable<=1'b0;
        vif.pwdata<=0;
        vif.paddr<=0;
        vif.pwrite<=1'b0;
        repeat(5) @(posedge vif.pclk);
        vif.presetn<=1'b1;
        repeat(5) @(posedge vif.pclk);
        $display("[DRV]: RESET DONE!");
        $display("------------------");
    endtask

    task run();
    forever begin 
       mbx.get(tr);

    //    WRITE OPERATION
    if(tr.oper==0) begin
        @(posedge vif.pclk);
        vif.psel<=1'b1;
        vif.penable<=1'b0;
        vif.pwdata<=tr.pwdata;
        vif.paddr<=tr.paddr;
        vif.pwrite<=1'b1;
        @(posedge vif.pclk);
        vif.penable<=1'b1;
        repeat(2)@(posedge vif.pclk);
        vif.psel<=1'b0;
        vif.penable<=1'b0;
        vif.pwrite<=1'b0;
        $display("[DRV]: DATA WRITE, PADDR: %0d, PWDATA: %0d",tr.paddr, tr.pwdata);
    end
    //      READ OPERATION
    else if(tr.oper==1) begin
        @(posedge vif.pclk);
        vif.psel<=1'b1;
        vif.penable<=1'b0;
        vif.paddr<=tr.paddr;
        vif.pwdata<=tr.pwdata;
        vif.pwrite<=1'b0;
        @(posedge vif.pclk);
        vif.penable<=1'b1;
        repeat(2)@(posedge vif.pclk);
        vif.psel<=1'b0;
        vif.penable<=1'b0;
        vif.pwrite<=1'b0;
        $display("[DRV]: DATA READ, PADDR: %0d",tr.paddr);
    end
    //     RANDOM OPERATION
    else if(tr.oper==2) begin
        @(posedge vif.pclk);
        vif.psel<=1'b1;
        vif.penable<=1'b0;
        vif.paddr<=tr.paddr;
        vif.pwdata<=tr.pwdata;
        vif.pwrite<=tr.pwrite;
        @(posedge vif.pclk);
        vif.penable<=1'b1;
        repeat(2)@(posedge vif.pclk);
        vif.psel<=1'b0;
        vif.penable<=1'b0;
        vif.pwrite<=1'b0;
        $display("[DRV]: RAMDOM OPERATION");
    end
    // ERROR
    else if(tr.oper==3) begin
        @(posedge vif.pclk);
        vif.psel<=1'b1;
        vif.penable<=1'b0;
        vif.paddr<=$urandom_range(32,100);
        vif.pwdata<=tr.pwdata;
        vif.pwrite<=tr.pwrite;
        @(posedge vif.pclk);
        vif.penable<=1'b1;
        repeat(2)@(posedge vif.pclk);
        vif.psel<=1'b0;
        vif.penable<=1'b0;
        vif.pwrite<=1'b0;
        $display("[DRV]: SLAVE ERROR");

    end
       ->drvnext;
    end
    endtask

endclass

/////////////////////////////////

class monitor;

    virtual apb_if vif;
    transaction tr;
    mailbox #(transaction) mbx;

    function new(mailbox #(transaction) mbx);
        this.mbx=mbx;
    endfunction

    task run();
        tr=new();
        forever begin
            @(posedge vif.pclk);
            if(vif.psel && !vif.penable)begin
                 @(posedge vif.pclk);
                 if(vif.psel && vif.penable && vif.pwrite)begin
                    @(posedge vif.pclk);
                    tr.pwdata=vif.pwdata;
                    tr.paddr=vif.paddr;
                    tr.pwrite=vif.pwrite;
                    tr.pslverr=vif.pslverr;
                    $display("[MON]: DATA WRITE PWDATA:%0d, PADDR:%0d", vif.pwdata,vif.paddr);
                    @(posedge vif.pclk);
                 end
                 else if(vif.psel && vif.penable && !vif.pwrite)begin
                    @(posedge vif.pclk);
                    tr.prdata=vif.prdata;
                    tr.pwrite=vif.pwrite;
                    tr.paddr=vif.paddr;
                    tr.pslverr=vif.pslverr;
                    @(posedge vif.pclk);
                    $display("[MON]: DATA WRITE PWDATA:%0d, PADDR:%0d", vif.pwdata,vif.paddr);
                 end
            mbx.put(tr);
            end
        end
    endtask

endclass

/////////////////////////////////

class scoreboard;
  
   mailbox #(transaction) mbx;
   transaction tr;
   event sconext;
  
  bit [31:0] pwdata[12] = '{default:0};
  bit [31:0] rdata;
  int index;
  
   function new(mailbox #(transaction) mbx);
      this.mbx = mbx;     
    endfunction;
  
  task run();
    forever begin
        mbx.get(tr);
        $display("[SCO] : DATA RCVD wdata:%0d rdata:%0d addr:%0d write:%0b", tr.pwdata, tr.prdata, tr.paddr, tr.pwrite);
        
        if( (tr.pwrite == 1'b1) && (tr.pslverr == 1'b0))  ///write access
        begin 
            pwdata[tr.paddr] = tr.pwdata;
            $display("[SCO] : DATA STORED DATA : %0d ADDR: %0d",tr.pwdata, tr.paddr);
        end
        else if((tr.pwrite == 1'b0) && (tr.pslverr == 1'b0))  ///read access
        begin
        rdata = pwdata[tr.paddr];    
            if( tr.prdata == rdata)
            $display("[SCO] : Data Matched"); 
        else
            $display("[SCO] : Data Mismatched"); 
        end 
        else if(tr.pslverr == 1'b1)
        begin
            $display("[SCO] : SLV ERROR DETECTED");
        end
    ->sconext;
    end
  endtask
 
  
endclass

/////////////////////////////////

class environment;

    generator gen;
    driver drv;
    scoreboard sco;
    monitor mon;
    event gd;
    event gs;
    mailbox #(transaction) mbxgd;
    mailbox #(transaction) mbxms;
    virtual apb_if vif;

    function new(virtual apb_if vif);
        this.vif=vif;
        mbxgd=new();
        mbxms=new();

        gen=new(mbxgd);
        drv=new(mbxgd);
        mon=new(mbxms);
        sco=new(mbxms);

        drv.vif=this.vif;
        mon.vif=this.vif;

        gen.drvnext=gd;
        drv.drvnext=gd;
        gen.sconext=gs;
        sco.sconext=gs;
    endfunction

    task preset();
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
    preset();
    test();
    post_test();
    endtask

endclass

/////////////////////////////////

module tb();

     apb_if vif();
     apb_ram dut(vif.presetn,vif.pclk,vif.paddr,vif.pwdata,vif.psel,vif.penable,vif.pwrite,vif.pready,vif.pslverr,vif.prdata);

    initial begin
        vif.pclk<=0;
    end
    always #10 vif.pclk=~vif.pclk;

    environment env;
    initial begin       
        env=new(vif);
        env.gen.count=20;
        env.run();
    end

    initial begin
        $dumpfile("dump.vcd");
        $dumpvars;
    end

endmodule