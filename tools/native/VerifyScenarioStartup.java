import ghidra.app.script.GhidraScript;
import com.google.gson.*;
import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.io.ByteArrayOutputStream;
import java.util.*;

/** Original startup instructions with explicit C-library and Toolbox boundaries. */
public class VerifyScenarioStartup extends GhidraScript {
    ActionOracleHarness h;
    Map<String, byte[]> files;
    Map<Long, Handle> handles;
    JsonArray calls;
    String scenario;
    long nextHandle;
    int steps;
    boolean terrainLoaded;
    Set<String> originalPaths;
    JsonObject stringLists;
    Path stockRoot;
    int newcCount;
    JsonArray menuItems;
    static final long STOP = 0x900000;
    void afterStartup(JsonObject output) throws Exception {}
    static class Handle {
        String path;
        int cursor;
        Handle(String path) { this.path = path; }
    }

    String cstr(long at) {
        ByteArrayOutputStream bytes = new ByteArrayOutputStream();
        for (int i=0;i<1024;i++) {
            int value=h.read(at+i,1)[0]&255;
            if(value==0) return bytes.toString(StandardCharsets.ISO_8859_1);
            bytes.write(value);
        }
        throw new IllegalArgumentException("unterminated C string");
    }
    void cstr(long at, String text) {
        byte[] bytes = text.getBytes(StandardCharsets.ISO_8859_1);
        h.write(at, Arrays.copyOf(bytes, bytes.length + 1));
    }
    void pstr(long at, String text) {
        byte[] value = text.getBytes(StandardCharsets.ISO_8859_1);
        byte[] bytes = new byte[value.length + 1];
        bytes[0] = (byte)value.length;
        System.arraycopy(value, 0, bytes, 1, value.length);
        h.write(at, bytes);
    }
    long arg(int offset) { return h.pointer(h.sp() + offset); }
    void result(long value) { h.cpu.writeRegister("D0", value); }
    void event(String name, String path, long count) {
        JsonObject row = new JsonObject();
        row.addProperty("service", name);
        row.addProperty("path", path);
        row.addProperty("count", count);
        row.addProperty("intercept_pc", Long.toHexString(h.pc()));
        row.addProperty("stack_word", Long.toHexString(h.pointer(h.sp())));
        calls.add(row);
    }
    void ret() { h.ret(); }

    boolean service(long pc) throws Exception {
        if (pc == 0x400168) {
            pstr(arg(4), Long.toString(arg(8))); ret(); return true;
        }
        if (pc == 0x400180) {
            long at = arg(4);
            byte[] bytes = h.read(at+1, h.read(at,1)[0] & 255);
            h.write(at, Arrays.copyOf(bytes, bytes.length+1));
            h.cpu.writeRegister("A0", at); ret(); return true;
        }
        if (pc == 0x400178) {
            int index=h.word(h.sp()+4), resource=h.word(h.sp()+6);
            JsonArray list=stringLists.getAsJsonArray(Integer.toString(resource));
            if (list==null || index<1 || index>list.size()) throw new Exception("missing STR# service input");
            byte[] value=HexFormat.of().parseHex(list.get(index-1).getAsString());
            h.write(arg(8),Arrays.copyOf(value,value.length+1));
            ret(); return true;
        }
        if (pc == 0x400070) {
            String path = cstr(arg(4)), mode = cstr(arg(8));
            if (path.startsWith(":")) path=path.substring(1);
            boolean write = mode.contains("w");
            if (write) files.put(path, new byte[0]);
            long id = 0;
            if (files.containsKey(path)) {
                id = ++nextHandle;
                handles.put(id, new Handle(path));
            }
            event("fopen:"+mode, path, id == 0 ? 0 : 1);
            h.cpu.writeRegister("A0", id); result(id); ret(); return true;
        }
        if (pc == 0x400048 || pc == 0x400050) {
            long target = arg(4), size = arg(8), count = arg(12);
            if (size < 1 || count < 1 || size*count > 1000000) throw new Exception("invalid I/O request");
            Handle handle = handles.get(arg(16));
            if (handle == null) throw new Exception("invalid file handle");
            int requested = Math.toIntExact(size*count), actual;
            byte[] data = files.get(handle.path);
            if (pc == 0x400048) {
                actual = Math.min(requested, data.length-handle.cursor);
                if (actual > 0) h.write(target, Arrays.copyOfRange(data, handle.cursor, handle.cursor+actual));
            } else {
                actual = requested;
                data = Arrays.copyOf(data, Math.max(data.length, handle.cursor+actual));
                System.arraycopy(h.read(target, actual), 0, data, handle.cursor, actual);
                files.put(handle.path, data);
            }
            handle.cursor += actual;
            event(pc == 0x400048 ? "fread" : "fwrite", handle.path, actual);
            result(actual/size); ret(); return true;
        }
        if (pc == 0x400068) {
            if (handles.remove(arg(4)) == null) throw new Exception("close of invalid handle");
            result(0); ret(); return true;
        }
        if (pc == 0x400078) {
            Handle handle = handles.get(arg(4));
            if (handle == null || h.word(h.sp()+12) != 0) throw new Exception("unsupported seek");
            handle.cursor = Math.toIntExact(arg(8));
            result(0); ret(); return true;
        }
        if (pc == 0x400148) {
            // Explicit disk-space query: 8 MiB available, OS status 0.
            h.value(arg(4), 4, 8*1024*1024);
            h.value(arg(8), 2, 0);
            long returnTo = h.pointer(h.sp());
            h.value(h.sp()+18, 2, 0); h.pop(18); h.jump(returnTo); return true;
        }
        if (pc == 0x400188) {
            long at = arg(4); pstr(at, cstr(at)); ret(); return true;
        }
        if (pc == 0x400140) {
            throw new Exception("unexpected unsupported Pascal library service");
        }
        if (pc == 0x123d1c) {
            event("flashmessage:presentation-only", cstr(arg(4)), 0); ret(); return true;
        }
        if (pc == 0x13b212 || pc == 0x135bb2) {
            event("menu-projection:presentation-only", "", 0); ret(); return true;
        }
        if (pc == 0x14cff6) {
            event("question:keep-existing-crate", "", 0); result(0); ret(); return true;
        }
        if (pc == 0x131182) {
            terrainLoaded = true;
            event("loadpixmap:original-instructions", "", h.read(0x44328e,1)[0]&255);
        }
        if (pc == 0x1312c0) {
            event("graphics-span-1312c0..131364:hosted-presentation", "", 0);
            h.jump(0x131364); return true;
        }
        if (pc == 0x13a6d4) {
            event("effective-registered-precondition", "", 1); result(1); ret(); return true;
        }
        if (pc == 0x138be8) throw new Exception("native scratch diagnostic " + h.word(h.sp()+4));
        if (pc == 0x16474a) throw new Exception("native warn diagnostic " + h.word(h.sp()+4));
        return false;
    }

    boolean trap(long pc) throws Exception {
        int opcode = h.word(pc) & 65535;
        if (opcode == 0xa99c) { // CountResources: NEWC resource type -> result word.
            if (h.pointer(h.sp())!=0x4e455743L) throw new Exception("unexpected CountResources type");
            event("CountResources:NEWC", "", newcCount);
            h.value(h.sp()+4,2,newcCount); h.pop(4);
        } else if (opcode == 0xa981) { h.pop(4);
        } else if (opcode == 0xa939 || opcode == 0xa93a) { h.pop(6);
        } else if (opcode == 0xa946) { // GetMenuItemText, named scenario item.
            int item=h.word(h.sp()+4);
            if (item<1 || item>menuItems.size()) throw new Exception("missing selected menu item");
            byte[] value=HexFormat.of().parseHex(menuItems.get(item-1).getAsString());
            byte[] label=new byte[value.length+1];label[0]=(byte)value.length;
            System.arraycopy(value,0,label,1,value.length);h.write(h.pointer(h.sp()),label); h.pop(10);
        } else if (opcode == 0xa99a) { h.pop(2);
        } else if (opcode == 0xa997) {
            long at=h.pointer(h.sp());
            byte[] value=h.read(at+1,h.read(at,1)[0]&255);
            String path=new String(value,StandardCharsets.ISO_8859_1);
            if (path.startsWith(":")) path=path.substring(1);
            if (!files.containsKey(path+".rsrc")) throw new Exception("resource fork missing: "+path);
            h.value(h.sp()+4,2,128); h.pop(4);
        } else { return false; }
        h.jump(pc+2); return true;
    }

    JsonObject runCase(Path root, JsonObject input, byte[] startup) throws Exception {
        h = new ActionOracleHarness(currentProgram);
        files = new LinkedHashMap<>(); handles = new HashMap<>(); calls = new JsonArray();
        scenario = input.get("scenario_name").getAsString(); nextHandle=0; steps=0; terrainLoaded=false;
        menuItems=input.getAsJsonArray("menu_items");
        JsonObject output = new JsonObject();
        output.addProperty("name",input.get("name").getAsString());
        Path level = Path.of(input.get("level_folder").getAsString());
        try {
            h.write(0x3fe210, startup);
            h.value(0x442560,2,newcCount-1); h.value(0x44274c,1,0);
            cstr(0x44260c,"Scenarios:"+scenario);
            try (var stream=Files.list(level)) {
                for (Path file : stream.filter(Files::isRegularFile).toList()) {
                    files.put("Scenarios:"+scenario+":0:"+file.getFileName(),Files.readAllBytes(file));
                }
            }
            for (String name:List.of("Data P BD","Data Swamp BD","Data Snow BD","Data Sub BD",
                "Data Desert BD","Data Lava BD","Data Castle BD","Data Techno BD","Data Biologic BD")) {
                files.put("Data Files:"+name,Files.readAllBytes(stockRoot.resolve(name)));
            }
            originalPaths=new HashSet<>(files.keySet());
            if (input.has("select_scenario") && input.get("select_scenario").getAsBoolean()) {
                h.enter(0x1366f8,0x6ffe00,STOP);
                h.value(0x6ffe04,2,newcCount-1); h.value(0x6ffe06,2,1);
                while(h.pc()!=STOP) {
                    long pc=h.pc();
                    if (++steps>20000) throw new Exception("selection budget");
                    if (service(pc)||trap(pc)) continue;
                    if(!h.cpu.step(monitor)) throw new Exception(h.cpu.getLastError());
                }
                output.addProperty("selection_result",h.cpu.readRegister("D0").intValue());
                if (h.cpu.readRegister("D0").intValue()!=1) throw new Exception("native scenario selection rejected");
            }
            h.enter(0x1538ba,0x6ffe00,STOP);
            ArrayDeque<String> recent = new ArrayDeque<>();
            while (h.pc()!=STOP) {
                long pc=h.pc();
                if (++steps > 2000000) throw new Exception("startup instruction budget");
                if (recent.size()==24) recent.removeFirst(); recent.addLast(Long.toHexString(pc));
                if (service(pc) || trap(pc)) continue;
                if (!h.cpu.step(monitor)) throw new Exception("at "+Long.toHexString(pc)+": "+h.cpu.getLastError());
            }
            output.addProperty("status","completed");
            output.addProperty("map",h.pointer(0x442774));
            output.addProperty("x",h.pointer(0x442778));
            output.addProperty("y",h.pointer(0x44277c));
            output.addProperty("stage_name",cstr(0x479ed8));
            output.addProperty("terrain_boundary_reached",terrainLoaded);
            int terrain=h.read(0x44328e,1)[0]&255;
            output.addProperty("terrain",terrain);
            output.addProperty("terrain_default_tile",h.word(0x435508+terrain*2));
            output.addProperty("terrain_tick_flag",h.word(0x435530+terrain*2));
            Path captures = root.resolve(input.get("name").getAsString()); Files.createDirectories(captures);
            for (var row : Map.of("headers",new long[]{0x478e42,4200},"regions",new long[]{0x443086,644},
                "visibility",new long[]{0x4358e6,8100},"floor",new long[]{0x4085b8,16200},
                "objects",new long[]{0x40c500,16200},"events",new long[]{0x414390,32400},
                "mission",new long[]{0x41d1c4,9280}).entrySet()) {
                Files.write(captures.resolve(row.getKey()+".bin"),h.read(row.getValue()[0],(int)row.getValue()[1]));
            }
            Files.write(captures.resolve("tile-properties.bin"),h.read(0x43167c,16000));
            JsonObject temporary = new JsonObject();
            for (var row : files.entrySet()) if (!originalPaths.contains(row.getKey())) {
                temporary.addProperty(row.getKey(),row.getValue().length);
            }
            output.add("temporary_files",temporary);
            afterStartup(output);
        } catch (Exception error) {
            output.addProperty("status","failed"); output.addProperty("error",error.toString());
            output.addProperty("pc",Long.toHexString(h.pc()));
        } finally {
            output.addProperty("steps",steps); output.add("services",calls); h.cpu.dispose();
        }
        return output;
    }

    public void run() throws Exception {
        Path spec=Path.of(getScriptArgs()[0]), output=Path.of(getScriptArgs()[1]);
        JsonObject input=JsonParser.parseString(Files.readString(spec)).getAsJsonObject();
        stringLists=input.getAsJsonObject("string_lists");
        stockRoot=Path.of(input.get("stock_root").getAsString());
        newcCount=input.get("newc_resource_count").getAsInt();
        JsonObject codeIdentity=new JsonObject();
        for (JsonElement code:input.getAsJsonArray("code_images")) {
            JsonObject row=code.getAsJsonObject();
            Path path=Path.of(row.get("path").getAsString());
            byte[] expected=Files.readAllBytes(path),actual=new byte[expected.length];
            currentProgram.getMemory().getBytes(toAddr(Long.parseLong(row.get("address").getAsString(),16)),actual);
            if(!Arrays.equals(actual,expected)) throw new Exception("program code identity mismatch: "+path);
            codeIdentity.addProperty(path.getFileName().toString(),ActionOracleHarness.sha256(path));
        }
        byte[] startup=Files.readAllBytes(Path.of(input.get("a5_image").getAsString()));
        JsonObject receipt=new JsonObject(); JsonArray cases=new JsonArray();
        receipt.add("code_identity",codeIdentity);
        for (JsonElement item:input.getAsJsonArray("cases")) cases.add(runCase(output.getParent(),item.getAsJsonObject(),startup));
        receipt.add("cases",cases);
        receipt.addProperty("authority","Original selectscenario 1366f8, setupnewgame 1538ba, resetgamefiles 14f96e, getfilename 136cfa, gettempfilename 136d86, Displaymissionname 133f3e, loadland 13107a and loadpixmap 131182 instructions. C-library filesystem/string, effective registration and explicit Toolbox/presentation services are controlled; graphics span 1312c0..131364 hosted. No ROM, rendered GUI or whole-game claim.");
        Files.writeString(output,new GsonBuilder().setPrettyPrinting().create().toJson(receipt)+"\n");
    }
}
