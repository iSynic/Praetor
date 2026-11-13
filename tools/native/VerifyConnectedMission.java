import com.google.gson.*;
import java.nio.file.*;
import java.util.*;

/** Original mission operations with presentation/combat explicitly hosted. */
public class VerifyConnectedMission extends VerifyScenarioStartup {
    JsonArray operations = new JsonArray();
    int choices;
    boolean completionPresented;
    void record(String kind, long value) {
        JsonObject row = new JsonObject(); row.addProperty("operation",kind); row.addProperty("value",value); operations.add(row);
    }
    @Override boolean service(long pc) throws Exception {
        if (pc == 0x400038) { result(Math.abs(h.word(h.sp()+4))); h.ret(); return true; }
        if (pc == 0x15dc34) {
            int message=h.word(h.sp()+6);record("message-presentation",message);
            if(message==1352)completionPresented=true;
            h.ret(); return true;
        }
        if (pc == 0x121596) { record("hosted-choice-selector",1); result(1); h.ret(); return true; }
        if (pc == 0x133a18 || pc == 0x13bb20 || pc == 0x1046e0 || pc == 0x10f186 || pc == 0x13ebde) {
            record("hosted-presentation-entry",pc); h.ret(); return true;
        }
        if (pc == 0x133c56) { h.ret(); return true; }
        if (pc == 0x153ca4) { result(1); h.ret(); return true; }
        if (pc == 0x114378) {
            record("battle-handoff",h.word(0x43874e));
            h.value(0x4386b2,1,0); h.value(0x435658,1,0); h.ret(); return true;
        }
        if (pc == 0x105748) {
            record("booty-arguments",h.pointer(h.sp()+4));
            record("treasure-credits",h.pointer(0x44331c+84));
            if(h.pointer(h.sp()+4)==65536) {
                byte[] expected=Arrays.copyOfRange(files.get("Scenarios:"+scenario+":0:Data TD"),174*88,175*88);
                if(!Arrays.equals(expected,h.read(0x44331c,88)))throw new Exception("explicit treasure row differs from export");
            }
            h.ret(); return true;
        }
        return super.service(pc);
    }
    @Override boolean trap(long pc) throws Exception {
        int opcode=h.word(pc)&65535;
        if (opcode==0xa873) { h.pop(4);h.jump(pc+2);return true; }
        if (opcode==0xa9bc) { record("GetPicture-hosted",h.word(h.sp()));h.value(h.sp()+2,4,0x600000);h.pop(2);h.jump(pc+2);return true; }
        if (opcode==0xa8f6) { record("DrawPicture-hosted",0);h.pop(8);h.jump(pc+2);return true; }
        return super.trap(pc);
    }
    @Override void afterStartup(JsonObject output) throws Exception {
        output.add("connected_operations",operations);
        StringBuilder listing=new StringBuilder();
        for(long[] range:new long[][]{{0x141918,0x141af0},{0x142830,0x1429a0},{0x143540,0x1435d8}}) {
            for(var instruction:currentProgram.getListing().getInstructions(toAddr(range[0]),true)) {
                long pc=instruction.getAddress().getOffset();if(pc>=range[1])break;
                listing.append(Long.toHexString(pc)).append(" ").append(instruction).append("\n");
            }
        }
        Files.writeString(Path.of(getScriptArgs()[1]).getParent().resolve("operation-instructions.txt"),listing);
        h.enter(0x1400e4,0x6ffe00,STOP);
        h.value(0x6ffe04,4,3); h.value(0x6ffe08,4,2);
        h.value(0x6ffe0c,2,0);h.value(0x6ffe0e,2,0);h.value(0x6ffe10,2,0);
        for(int step=0;step<100000;step++) {
            long pc=h.pc(); if(pc==STOP) break;
            if(service(pc)||trap(pc)){if(completionPresented)break;continue;}
            if(!h.cpu.step(monitor))throw new Exception("connected at "+Long.toHexString(pc)+": "+h.cpu.getLastError());
            if(step==99999)throw new Exception("connected instruction budget at "+Long.toHexString(h.pc()));
        }
        output.add("connected_operations",operations);
        if(!completionPresented)throw new Exception("completion story not reached");
        output.addProperty("completion_stage",h.word(0x435500));
        output.addProperty("completion_map",h.pointer(0x442774));
        output.addProperty("completion_x",h.pointer(0x442764));
        output.addProperty("completion_y",h.pointer(0x442768));
    }
}
