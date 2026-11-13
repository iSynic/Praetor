import ghidra.app.script.GhidraScript;
import ghidra.app.decompiler.*;
import ghidra.program.model.listing.*;
import java.nio.file.*;

/** Writes the decompilation of the named routines (arguments) to the output directory. */
public class AuditDecompile extends GhidraScript {
    public void run() throws Exception {
        String[] args = getScriptArgs();
        Path out = Paths.get(args[0]);
        Files.createDirectories(out);
        DecompInterface d = new DecompInterface();
        d.openProgram(currentProgram);
        for (int i = 1; i < args.length; i++) {
            Function f = null;
            for (Function g : currentProgram.getFunctionManager().getFunctions(true)) if (g.getName().equals(args[i])) f = g;
            if (f == null) { try { f = getFunctionAt(toAddr(Long.parseLong(args[i].replace("0x",""), 16))); } catch (Exception e) {} }
            if (f == null) { println("MISSING " + args[i]); continue; }
            DecompileResults r = d.decompileFunction(f, 60, monitor);
            String text = r.decompileCompleted() ? r.getDecompiledFunction().getC() : "DECOMPILE FAILED " + r.getErrorMessage();
            Files.writeString(out.resolve(f.getName() + "_" + f.getEntryPoint() + ".c"), text);
            println("WROTE " + f.getName() + " " + f.getEntryPoint());
        }
    }
}
