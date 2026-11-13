import ghidra.app.script.GhidraScript;
import ghidra.app.decompiler.*;
import ghidra.program.model.listing.*;
import java.nio.file.*;

/** Writes the decompilation of every routine. Argument: output directory. */
public class AuditDecompileAll extends GhidraScript {
    public void run() throws Exception {
        Path out = Paths.get(getScriptArgs()[0]);
        Files.createDirectories(out);
        DecompInterface d = new DecompInterface();
        d.openProgram(currentProgram);
        int n = 0;
        for (Function f : currentProgram.getFunctionManager().getFunctions(true)) {
            if (monitor.isCancelled()) break;
            DecompileResults r = d.decompileFunction(f, 60, monitor);
            String text = r.decompileCompleted() ? r.getDecompiledFunction().getC() : "DECOMPILE FAILED " + r.getErrorMessage();
            Files.writeString(out.resolve(f.getName() + "_" + f.getEntryPoint() + ".c"), text);
            n++;
        }
        println("DECOMPILED " + n);
    }
}
