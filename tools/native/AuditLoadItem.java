import ghidra.app.script.GhidraScript;
import com.google.gson.*;
import java.nio.file.*;

/** Runs the original loaditem on marker tables for chosen ids; no scenario data is involved. Argument: output file. */
public class AuditLoadItem extends GhidraScript {
    static final long[] TABLES = {0x4537fe, 0x46225e, 0x45ad2e, 0x46978e, 0x470cbe};
    static final long DESTINATION = 0x45363c;
    public void run() throws Exception {
        JsonArray rows = new JsonArray();
        int[] ids = {0, 1, 199, 200, 399, 400, 599, 600, 799, 800, 999, 1000, 1199, 1999, 2000, -1, -5, -999, -1000, -32768, 32767};
        for (int id : ids) {
            ActionOracleHarness h = new ActionOracleHarness(currentProgram);
            try {
                for (int t = 0; t < TABLES.length; t++) {
                    for (int r = 0; r < 200; r++) {
                        byte[] row = new byte[150];
                        row[0] = (byte) (t + 1);
                        row[1] = (byte) r;
                        h.write(TABLES[t] + (long) r * 150, row);
                    }
                }
                byte[] sentinel = new byte[150];
                java.util.Arrays.fill(sentinel, (byte) 0xEE);
                h.write(DESTINATION, sentinel);
                long stack = 0x700000, end = 0x900000;
                h.enter(0x130afe, stack, end);
                h.value(stack + 4, 2, id & 0xffff);
                boolean done = false;
                for (int step = 0; step < 20000; step++) {
                    if (h.pc() == end) { done = true; break; }
                    if (!h.cpu.step(monitor)) throw new Exception("stopped at " + Long.toHexString(h.pc()) + ": " + h.cpu.getLastError());
                }
                if (!done) throw new Exception("loaditem did not return for " + id);
                byte[] got = h.read(DESTINATION, 2);
                JsonObject row = new JsonObject();
                row.addProperty("id", id);
                boolean loaded = (got[0] & 0xff) != 0xEE;
                row.addProperty("loaded", loaded);
                if (loaded) { row.addProperty("table", got[0] & 0xff); row.addProperty("row", got[1] & 0xff); }
                rows.add(row);
            } finally { h.cpu.dispose(); }
        }
        Files.writeString(Paths.get(getScriptArgs()[0]), new GsonBuilder().setPrettyPrinting().create().toJson(rows));
        println("ROWS " + rows.size());
    }
}
