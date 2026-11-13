import ghidra.app.script.GhidraScript;
import com.google.gson.*;
import java.nio.file.*;
import java.util.*;

/** Bounded original newland lookup; no story execution or presentation claim. */
public class VerifyTriggerFields extends GhidraScript {
    Path baseline;
    JsonArray cases=new JsonArray();
    JsonArray conditions=new JsonArray();
    JsonArray movement=new JsonArray();
    void movementGate(int value) throws Exception {
        ActionOracleHarness h=new ActionOracleHarness(currentProgram);
        try {
            h.write(0x100000,Files.readAllBytes(baseline.resolve("rebuilt/analysis/ghidra/startup/code1-mapped.bin")));
            h.write(0x3fe210,Files.readAllBytes(baseline.resolve("rebuilt/analysis/ghidra/startup/a5-mapped.bin")));
            h.value(0x442778,4,0);h.value(0x44277c,4,0);h.value(0x442764,4,2);h.value(0x442768,4,2);h.value(0x442736,1,1);h.value(0x442737,1,0);
            h.value(0x414390+(3*90+2)*4,4,value);h.value(0x4085b8+(3*90+2)*2,2,155);h.value(0x4386b2,1,0);
            h.enter(0x109766,0x700000,0x900000);h.cpu.writeRegister("D0",155);
            boolean called=false,done=false;
            for(int step=0;step<1000;step++) {
                long pc=h.pc();
                if(pc==0x1098ae){done=true;break;}
                if(pc==0x1400e4){called=true;done=true;if(h.pointer(h.sp()+4)!=3||h.pointer(h.sp()+8)!=2)throw new Exception("movement newland coordinates");break;}
                if(pc==0x13ea82){h.value(0x442764,4,3);h.ret();continue;}
                if(pc==0x15e148){h.ret();continue;}
                if(pc<0x109766||pc>0x1098ae)throw new Exception("unexpected movement boundary "+Long.toHexString(pc));
                if(!h.cpu.step(monitor))throw new Exception(h.cpu.getLastError());
            }
            if(!done||called!=(value>0))throw new Exception("native movement gate mismatch");
            JsonObject row=new JsonObject();row.addProperty("event_value",value);row.addProperty("calls_newland",called);row.addProperty("event_address",Long.toHexString(0x414390+(3*90+2)*4));row.addProperty("services","moveparty position reply and timeclick return; original gate, call setup and coordinates execute");movement.add(row);
        } finally {h.cpu.dispose();}
    }
    void condition(String name,long entry,long stop,int expected,int mode) throws Exception {
        ActionOracleHarness h=new ActionOracleHarness(currentProgram);
        try {
            h.write(0x100000,Files.readAllBytes(baseline.resolve("rebuilt/analysis/ghidra/startup/code1-mapped.bin")));
            h.write(0x443396,new byte[156]);h.write(0x438768,new byte[16]);h.write(0x443432,new byte[106]);
            h.enter(entry,0x700000,0x900000);
            if(name.startsWith("physical")) {
                h.value(0x4433f6,1,2);
                if(mode!=0){h.value(0x4433f8+2,1,1);h.value(0x438768+4,2,1);}
                if(mode==2)h.value(0x438768+6,2,1);
            }else if(name.startsWith("item")) {
                h.value(0x44719a,2,123);h.value(0x44341e+8,2,mode==0?122:123);h.value(0x443428+4,1,3);
            }else if(name.startsWith("spell")) {
                h.cpu.writeRegister("D5",42);h.value(0x443400+6,2,mode==0?43:mode==2?3:42);h.value(0x443414+3,1,2);
            }else {
                h.value(0x4471ea,2,4);h.value(0x443492+3,1,mode);
            }
            int services=0;boolean done=false;
            for(int steps=0;steps<2000;steps++) {
                long pc=h.pc();if(pc==stop){done=true;break;}
                if(pc==0x13145c&&name.equals("spell-category")){h.value(0x443761,1,3);services++;h.ret();continue;}
                if(pc<entry-0x200||pc>stop+0x200)throw new Exception("unexpected condition branch "+Long.toHexString(pc));
                if(!h.cpu.step(monitor))throw new Exception(Long.toHexString(pc)+":"+h.cpu.getLastError());
            }
            if(!done)throw new Exception("condition instruction budget");
            int result=name.startsWith("choice")?h.cpu.readRegister("D0").shortValue():h.cpu.readRegister("D4").byteValue();
            if(result!=expected)throw new Exception(name+" expected "+expected+" got "+result);
            JsonObject row=new JsonObject();row.addProperty("case",name);row.addProperty("entry",Long.toHexString(entry));row.addProperty("stop",Long.toHexString(stop));row.addProperty("selector",result);row.addProperty("spell_definition_services",services);conditions.add(row);
        } finally {h.cpu.dispose();}
    }
    void walking(String name,int chance,int draw,boolean duplicate,boolean match,int cell) throws Exception {
        ActionOracleHarness h=new ActionOracleHarness(currentProgram);
        try {
            h.write(0x100000,Files.readAllBytes(baseline.resolve("rebuilt/analysis/ghidra/startup/code1-mapped.bin")));
            h.write(0x3fe210,Files.readAllBytes(baseline.resolve("rebuilt/analysis/ghidra/startup/a5-mapped.bin")));
            byte[] table=new byte[4200]; Arrays.fill(table,(byte)0x55);
            java.nio.ByteBuffer b=java.nio.ByteBuffer.wrap(table);
            for(int i=0;i<100;i++) b.putInt(i*42,-1);
            int slot=13,key=2*10000+11*100+7;
            b.putInt(slot*42,match?key:key+1);table[slot*42+7]=(byte)chance;
            if(duplicate){b.putInt((slot+1)*42,key);table[(slot+1)*42+7]=100;}
            h.write(0x478e42,table);h.write(0x479eaa,new byte[42]);h.value(0x442774,4,2);
            // The separate imported map event layer is deliberately varied.
            h.value(0x414390+(7*90+11)*4,4,cell);
            long sp=0x700000;h.enter(0x1400e4,sp,0x900000);h.value(sp+4,4,7);h.value(sp+8,4,11);h.value(sp+12,2,0);h.value(sp+14,2,0);h.value(sp+16,2,0);
            int draws=0;boolean selected=false,done=false;
            for(int steps=0;steps<20000;steps++) {
                long pc=h.pc();
                if(pc==0x14032e){selected=true;done=true;break;}
                if(pc==0x900000){done=true;break;}
                if(pc==0x133c56){h.ret();continue;}
                if(pc==0x153ca4){draws++;h.cpu.writeRegister("D0",draw);h.ret();continue;}
                if(pc>=0x400000&&pc<0x401000)throw new Exception("Unqualified external "+Long.toHexString(pc));
                if(!h.cpu.step(monitor))throw new Exception(Long.toHexString(pc)+":"+h.cpu.getLastError());
            }
            if(!done)throw new Exception("walking instruction budget");
            if(!Arrays.equals(table,h.read(0x478e42,4200)))throw new Exception("source table changed");
            if(selected&&!Arrays.equals(Arrays.copyOfRange(table,slot*42,(slot+1)*42),h.read(0x479eaa,42)))throw new Exception("wrong full header selected");
            JsonObject r=new JsonObject();r.addProperty("case",name);r.addProperty("chance",chance);r.addProperty("draw",draw);r.addProperty("draws",draws);r.addProperty("selected",selected);r.addProperty("map_cell",cell);r.addProperty("selected_slot",selected?h.word(0x4427c2):-1);r.addProperty("table_unchanged",true);cases.add(r);
        } finally {h.cpu.dispose();}
    }
    public void run() throws Exception {
        baseline=Path.of(getScriptArgs()[0]);Path out=Path.of(getScriptArgs()[1]);
        walking("chance100-cell0",100,50,false,true,0);
        walking("chance100-cell-positive",100,50,false,true,21107);
        walking("chance0-shadows-second",0,1,true,true,21107);
        walking("retired",-1,1,false,true,0);
        walking("negative",-128,1,false,true,0);
        walking("boundary-fail",49,50,false,true,0);
        walking("boundary-pass",50,50,false,true,0);
        walking("missing",100,1,false,false,0);
        condition("physical-empty-fails",0x122a5c,0x122adc,4,0);
        condition("physical-exact-set",0x122a5c,0x122adc,2,1);
        condition("physical-extra-action-fails",0x122a5c,0x122adc,4,2);
        condition("item-last-alternative",0x1229ea,0x122adc,3,1);
        condition("item-no-match",0x1229ea,0x122adc,4,0);
        condition("spell-exact-id",0x122918,0x122adc,2,1);
        condition("spell-no-match",0x122918,0x122adc,4,0);
        condition("spell-category",0x122918,0x122adc,2,2);
        condition("choice-remapped-branch",0x12182e,0x121846,2,2);
        condition("choice-signed-selector",0x12182e,0x121846,-4,-4);
        movementGate(-1);movementGate(0);movementGate(203);
        JsonObject result=new JsonObject();result.addProperty("authority","Original movement caller 109766 gates newland on positive LD event cells; direct newland lookup executes from entry through selection/rejection, plus bounded original physical/item/spell matching and signed choice return. Sustained audio, deterministic Rand and one spell-definition lookup are explicit services. Stops before script execution and modal teardown. No instruction patches.");result.add("walking",cases);
        result.add("conditions",conditions);result.add("movement",movement);Files.writeString(out.resolve("capture.json"),result+"\n");
        StringBuilder listing=new StringBuilder();
        for(long[] range:new long[][]{{0x109766,0x10988e},{0x1228d0,0x122adc},{0x1217ca,0x121854},{0x140282,0x14032e}}){
            for(var instruction:currentProgram.getListing().getInstructions(toAddr(range[0]),true)) {long pc=instruction.getAddress().getOffset();if(pc>=range[1])break;listing.append(instruction.toString()).append(" @").append(Long.toHexString(pc)).append("\n");}
        }
        Files.writeString(out.resolve("condition-instructions.txt"),listing);
    }
}
