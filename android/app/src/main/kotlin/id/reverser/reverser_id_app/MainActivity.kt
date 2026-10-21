package id.reverser.reverser_id_app

import android.os.Handler
import android.os.Looper
import dalvik.system.DexClassLoader
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.util.concurrent.atomic.AtomicInteger
import java.util.zip.CRC32
import java.util.zip.ZipEntry
import java.util.zip.ZipFile
import java.util.zip.ZipOutputStream
import java.security.KeyStore
import java.security.PrivateKey
import java.security.cert.X509Certificate
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val channelName = "id.reverser/patch"
    private val io = Executors.newSingleThreadExecutor()
    private val ui = Handler(Looper.getMainLooper())

    private var apktoolCl: ClassLoader? = null
    private var apksignerCl: ClassLoader? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                val a = call.arguments as? Map<*, *> ?: emptyMap<String, Any>()
                fun s(k: String) = a[k] as String
                io.execute {
                    try {
                        val out: Any = when (call.method) {
                            "apktool" -> {
                                @Suppress("UNCHECKED_CAST")
                                runApktool(s("jar"), a["args"] as List<String>, s("tmp"), s("opt"))
                                "ok"
                            }
                            "sign" -> {
                                signApk(s("signer"), s("opt"), s("input"), s("output"),
                                    s("keystore"), s("alias"), s("pass"))
                                "ok"
                            }
                            "installedApk" -> installedApk(s("package"), s("dest"))
                            "dexDecode" -> {
                                @Suppress("UNCHECKED_CAST")
                                dexDecode(s("jar"), s("opt"), s("apk"),
                                    a["dex"] as List<String>, s("out")).toString()
                            }
                            "dexBuild" -> {
                                @Suppress("UNCHECKED_CAST")
                                dexBuild(s("jar"), s("opt"), s("apk"),
                                    a["files"] as List<String>, s("smali"), s("output"),
                                    (a["api"] as String).toInt())
                                "ok"
                            }
                            else -> { ui.post { result.notImplemented() }; return@execute }
                        }
                        ui.post { result.success(out) }
                    } catch (t: Throwable) {
                        val c = t.cause ?: t
                        ui.post {
                            result.error("ERR", "${c.javaClass.simpleName}: ${c.message}",
                                c.stackTraceToString().take(3000))
                        }
                    }
                }
            }
    }

    private fun readOnlyDex(path: String): String {
        val f = File(path)
        f.setWritable(false, false)
        f.setReadOnly()
        return path
    }

    private fun installedApk(pkg: String, dest: String): String {
        val info = packageManager.getPackageInfo(pkg, 0)
        val src = info.applicationInfo?.sourceDir
            ?: throw IllegalStateException("no base apk for $pkg")
        val out = File(dest)
        out.parentFile?.mkdirs()
        File(src).copyTo(out, overwrite = true)
        return out.path
    }

    private fun apktoolClassLoader(jar: String, opt: String): ClassLoader {
        return apktoolCl ?: DexClassLoader(readOnlyDex(jar), opt, null,
            javaClass.classLoader).also { apktoolCl = it }
    }

    private fun smaliDirFor(dexName: String): String =
        if (dexName == "classes.dex") "smali"
        else "smali_classes" + dexName.removePrefix("classes").removeSuffix(".dex")

    private fun dexDecode(
        jar: String, opt: String, apk: String, dexNames: List<String>, outRoot: String
    ): Int {
        val cl = apktoolClassLoader(jar, opt)
        val dexBackedCls =
            Class.forName("com.android.tools.smali.dexlib2.dexbacked.DexBackedDexFile", true, cl)
        val sdCls = Class.forName("brut.androlib.smali.SmaliDecoder", true, cl)

        val sd = sdCls.getConstructor(File::class.java, Boolean::class.javaPrimitiveType)
            .newInstance(File(apk), true)
        val container = sdCls.getField("mDexContainer").get(sd)
        val entries = container.javaClass.getMethod("getEntries").invoke(container)
            as java.util.TreeMap<*, *>
        val decodeFile = sdCls.getMethod("decodeFile", dexBackedCls, File::class.java)
        for (dexName in dexNames) {
            val entry = entries[dexName] ?: continue

            val dexFile = runCatching {
                entry.javaClass.getMethod("getDexFile").invoke(entry)
            }.getOrDefault(entry)
            val smaliDir = File(outRoot, smaliDirFor(dexName)).apply { mkdirs() }
            decodeFile.invoke(sd, dexFile, smaliDir)
        }
        val api = (sdCls.getField("mInferredApiLevel").get(sd) as AtomicInteger).get()
        return if (api in 1..29) api else 29
    }

    private fun dexBuild(
        jar: String, opt: String, apk: String, files: List<String>,
        smaliRoot: String, outApk: String, apiLevel: Int
    ) {
        val cl = apktoolClassLoader(jar, opt)
        val api = if (apiLevel in 1..29) apiLevel else 29
        val opcodesCls = Class.forName("com.android.tools.smali.dexlib2.Opcodes", true, cl)
        val opcodes = opcodesCls.getConstructor(Int::class.javaPrimitiveType).newInstance(api)
        val dexBuilderCls =
            Class.forName("com.android.tools.smali.dexlib2.writer.builder.DexBuilder", true, cl)
        val fdsCls =
            Class.forName("com.android.tools.smali.dexlib2.writer.io.FileDataStore", true, cl)
        val sbCls = Class.forName("brut.androlib.smali.SmaliBuilder", true, cl)
        val sb = sbCls.getConstructor(Int::class.javaPrimitiveType).newInstance(api)
        val buildFile = sbCls.getMethod("buildFile", File::class.java, dexBuilderCls)
        val writeToBuilder = dexBuilderCls.getMethod("writeTo", fdsCls)
        val fdsCtor = fdsCls.getConstructor(File::class.java)

        val factoryCls = Class.forName("com.android.tools.smali.dexlib2.DexFileFactory", true, cl)
        val loadDex = factoryCls.getMethod("loadDexFile", String::class.java, opcodesCls)
        val dexFileIface = Class.forName("com.android.tools.smali.dexlib2.iface.DexFile", true, cl)
        val writeDex = factoryCls.getMethod("writeDexFile", String::class.java, dexFileIface)
        val getClassesM = dexFileIface.getMethod("getClasses")
        val getTypeM =
            Class.forName("com.android.tools.smali.dexlib2.iface.ClassDef", true, cl).getMethod("getType")

        val sdCls = Class.forName("brut.androlib.smali.SmaliDecoder", true, cl)
        val sd = sdCls.getConstructor(File::class.java, Boolean::class.javaPrimitiveType)
            .newInstance(File(apk), true)
        val container = sdCls.getField("mDexContainer").get(sd)
        val entries = container.javaClass.getMethod("getEntries").invoke(container)
            as java.util.TreeMap<*, *>

        @Suppress("UNCHECKED_CAST")
        fun classesOf(d: Any) = getClassesM.invoke(d) as Collection<Any>
        fun typeOf(c: Any) = getTypeM.invoke(c) as String

        val byDex = files.filterNot { it.startsWith("res/") }.groupBy {
            val seg = it.substringBefore('/')
            if (seg == "smali") "classes.dex"
            else "classes" + seg.removePrefix("smali_classes") + ".dex"
        }

        val newDex = HashMap<String, ByteArray>()
        for ((dexName, changedFiles) in byDex) {
            val orig = entries[dexName] ?: continue

            val db = dexBuilderCls.getConstructor(opcodesCls).newInstance(opcodes)
            for (rel in changedFiles) {
                val f = File(smaliRoot, rel.replace('/', File.separatorChar))
                val ok = buildFile.invoke(sb, f, db) as Boolean
                if (!ok) throw IllegalStateException("smali assemble failed: $rel")
            }
            val tmpChanged = File.createTempFile("chg", ".dex")
            writeToBuilder.invoke(db, fdsCtor.newInstance(tmpChanged))
            val changed = loadDex.invoke(null, tmpChanged.path, opcodes)
            val changedTypes = classesOf(changed).mapTo(HashSet()) { typeOf(it) }

            val merged = LinkedHashSet<Any>()
            for (c in classesOf(orig)) if (typeOf(c) !in changedTypes) merged.add(c)
            merged.addAll(classesOf(changed))

            val handler = java.lang.reflect.InvocationHandler { _, m, _ ->
                when (m.name) {
                    "getClasses" -> merged
                    "getOpcodes" -> opcodes
                    "toString" -> "RidDexFile"
                    "hashCode" -> dexName.hashCode()
                    "equals" -> false
                    else -> null
                }
            }
            val proxy = java.lang.reflect.Proxy.newProxyInstance(
                cl, arrayOf(dexFileIface), handler)
            val tmpOut = File.createTempFile("out", ".dex")
            writeDex.invoke(null, tmpOut.path, proxy)
            newDex[dexName] = tmpOut.readBytes()
            tmpChanged.delete()
            tmpOut.delete()
        }
        spliceApk(apk, outApk, newDex)
    }

    private fun spliceApk(src: String, dst: String, replace: Map<String, ByteArray>) {
        val sigRe = Regex("^META-INF/.*\\.(SF|RSA|DSA|EC|MF)$", RegexOption.IGNORE_CASE)
        File(dst).parentFile?.mkdirs()
        val counter = object : java.io.FilterOutputStream(
            java.io.BufferedOutputStream(FileOutputStream(dst), 1 shl 16)) {
            var count = 0L
            override fun write(b: Int) { out.write(b); count++ }
            override fun write(b: ByteArray, off: Int, len: Int) {
                out.write(b, off, len); count += len
            }
        }
        ZipOutputStream(counter).use { zout ->
            zout.setLevel(java.util.zip.Deflater.BEST_SPEED)
            ZipFile(src).use { zin ->
                val e = zin.entries()
                while (e.hasMoreElements()) {
                    val entry = e.nextElement()
                    if (entry.isDirectory || sigRe.matches(entry.name)) continue
                    val repl = replace[entry.name]
                    val ne = ZipEntry(entry.name)
                    if (entry.method == ZipEntry.STORED) {
                        ne.method = ZipEntry.STORED
                        if (repl != null) {
                            ne.size = repl.size.toLong()
                            ne.crc = CRC32().apply { update(repl) }.value
                        } else {
                            ne.size = entry.size
                            ne.crc = entry.crc
                        }
                        val align = if (ne.name.endsWith(".so")) 16384L else 4L
                        val header = 30L + ne.name.toByteArray(Charsets.UTF_8).size
                        val pad = ((align - (counter.count + header) % align) % align).toInt()
                        if (pad > 0) ne.setExtra(ByteArray(pad))
                    } else {
                        ne.method = ZipEntry.DEFLATED
                    }
                    zout.putNextEntry(ne)
                    if (repl != null) {
                        zout.write(repl)
                    } else {
                        zin.getInputStream(entry).use { it.copyTo(zout, 1 shl 16) }
                    }
                    zout.closeEntry()
                }
            }
        }
    }

    private fun runApktool(jar: String, toolArgs: List<String>, tmp: String, opt: String) {
        File(tmp).mkdirs()
        File(opt).mkdirs()
        System.setProperty("sun.arch.data.model", "64")
        System.setProperty("java.io.tmpdir", tmp)
        System.setProperty("java.awt.headless", "true")
        val cl = apktoolCl ?: DexClassLoader(readOnlyDex(jar), opt, null,
            javaClass.classLoader).also { apktoolCl = it }
        val main = Class.forName("brut.apktool.Main", true, cl)
        main.getMethod("main", Array<String>::class.java)
            .invoke(null, toolArgs.toTypedArray())
    }

    private fun signApk(
        signerJar: String, opt: String, input: String, output: String,
        keystore: String, alias: String, pass: String
    ) {
        File(opt).mkdirs()
        val cl = apksignerCl ?: DexClassLoader(readOnlyDex(signerJar), opt, null,
            javaClass.classLoader).also { apksignerCl = it }
        val pw = pass.toCharArray()
        val ks = KeyStore.getInstance("PKCS12")
        FileInputStream(keystore).use { ks.load(it, pw) }
        val key = ks.getKey(alias, pw) as PrivateKey
        val chain = ks.getCertificateChain(alias).map { it as X509Certificate }

        val scbCls = Class.forName(
            "com.android.apksig.ApkSigner\$SignerConfig\$Builder", true, cl)
        val ctor = scbCls.getConstructor(
            String::class.java, PrivateKey::class.java, List::class.java)
        val scb = ctor.newInstance("CERT", key, chain)
        val signerConfig = scbCls.getMethod("build").invoke(scb)

        val abCls = Class.forName("com.android.apksig.ApkSigner\$Builder", true, cl)
        val ab = abCls.getConstructor(List::class.java).newInstance(listOf(signerConfig))
        abCls.getMethod("setInputApk", File::class.java).invoke(ab, File(input))
        abCls.getMethod("setOutputApk", File::class.java).invoke(ab, File(output))
        val b = Boolean::class.javaPrimitiveType
        abCls.getMethod("setV1SigningEnabled", b).invoke(ab, true)
        abCls.getMethod("setV2SigningEnabled", b).invoke(ab, true)
        abCls.getMethod("setV3SigningEnabled", b).invoke(ab, true)
        val signer = abCls.getMethod("build").invoke(ab)
        signer.javaClass.getMethod("sign").invoke(signer)
    }
}
