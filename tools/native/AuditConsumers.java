import ghidra.app.script.GhidraScript;
import ghidra.program.model.listing.*;
import ghidra.program.model.address.*;
import ghidra.program.model.symbol.*;
import ghidra.program.model.scalar.*;
import java.nio.file.*;
import java.util.*;

/** Lists every instruction that refers to a data range: by reference or by an address operand. Arguments: output file, first address, last address (hex). */
public class AuditConsumers extends GhidraScript {
    public void run() throws Exception {
        String[] args = getScriptArgs();
        long lo = Long.parseLong(args[1], 16), hi = Long.parseLong(args[2], 16);
        StringBuilder out = new StringBuilder();
        Listing listing = currentProgram.getListing();
        InstructionIterator it = listing.getInstructions(true);
        int hits = 0;
        while (it.hasNext()) {
            Instruction ins = it.next();
            Set<Long> targets = new TreeSet<>();
            for (Reference r : ins.getReferencesFrom()) {
                long t = r.getToAddress().getOffset();
                if (t >= lo && t <= hi) targets.add(t);
            }
            for (int op = 0; op < ins.getNumOperands(); op++) {
                for (Object o : ins.getOpObjects(op)) {
                    if (o instanceof Scalar) {
                        long t = ((Scalar) o).getUnsignedValue();
                        if (t >= lo && t <= hi) targets.add(t);
                    } else if (o instanceof Address) {
                        long t = ((Address) o).getOffset();
                        if (t >= lo && t <= hi) targets.add(t);
                    }
                }
            }
            if (targets.isEmpty()) continue;
            Function f = getFunctionContaining(ins.getAddress());
            for (long t : targets) {
                out.append(String.format("%s\t%s\t%x\t%d\t%s%n", ins.getAddress(), f == null ? "-" : f.getName(), t, t - lo, ins.toString()));
                hits++;
            }
        }
        Files.writeString(Paths.get(args[0]), out.toString());
        println("HITS " + hits);
    }
}
