package ch.stromheftli.app

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.tom_roush.pdfbox.android.PDFBoxResourceLoader
import com.tom_roush.pdfbox.pdmodel.PDDocument
import com.tom_roush.pdfbox.text.PDFTextStripper
import java.io.File
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private lateinit var channel: MethodChannel
    private val worker = Executors.newSingleThreadExecutor()
    private var picker: MethodChannel.Result? = null
    private val pending = ArrayDeque<String>()
    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        channel = MethodChannel(engine.dartExecutor.binaryMessenger, "stromheftli/files")
        channel.setMethodCallHandler { call, reply ->
            when (call.method) {
                "directory" -> reply.success(filesDir.absolutePath)
                "takeShare" -> reply.success(pending.removeFirstOrNull())
                "extractPdf" -> {
                    val path = call.arguments as String
                    worker.execute {
                        try {
                            PDFBoxResourceLoader.init(applicationContext)
                            val text = PDDocument.load(File(path)).use { document ->
                                PDFTextStripper().apply { sortByPosition = true }.getText(document)
                            }
                            runOnUiThread { reply.success(text) }
                        } catch (e: Exception) {
                            runOnUiThread { reply.error("pdfText", e.message, null) }
                        }
                    }
                }
                "openPdf" -> {
                    startActivity(Intent(this, PdfActivity::class.java).putExtra("path",call.arguments as String))
                    reply.success(null)
                }
                "pick" -> {
                    if (picker != null) reply.error("busy","Dateiauswahl läuft",null)
                    else {
                        picker = reply
                        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).addCategory(Intent.CATEGORY_OPENABLE)
                        intent.type = if (call.arguments == "pdf") "application/pdf" else "*/*"
                        try { startActivityForResult(intent, 47) }
                        catch (e: Exception) { picker = null; reply.error("picker",e.message,null) }
                    }
                }
                else -> reply.notImplemented()
            }
        }
    }
    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        if (state == null) receive(intent)
    }
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        receive(intent)
    }
    private fun receive(intent: Intent) {
        if (intent.action != Intent.ACTION_SEND || intent.type != "application/pdf") return
        val uri = intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM) ?: return
        copyUri(uri, null)
    }
    override fun onActivityResult(request: Int, result: Int, data: Intent?) {
        super.onActivityResult(request,result,data)
        if (request != 47) return
        val reply = picker ?: return
        picker = null
        val uri = data?.data
        if (result == Activity.RESULT_OK && uri != null) copyUri(uri,reply) else reply.success(null)
    }
    private fun copyUri(uri: Uri, reply: MethodChannel.Result?) {
        if (uri.scheme != "content") { reply?.error("uri","Ungültige Dateiquelle",null); return }
        worker.execute {
            val file = File.createTempFile("import-", ".tmp",cacheDir)
            try {
                val input = contentResolver.openInputStream(uri) ?: error("Datei nicht lesbar")
                input.use { source -> file.outputStream().use { target -> source.copyTo(target) } }
                runOnUiThread {
                    if (reply != null) reply.success(file.absolutePath)
                    else { pending.addLast(file.absolutePath); channel.invokeMethod("shareReady",null) }
                }
            } catch (e: Exception) {
                file.delete()
                runOnUiThread { if(reply!=null) reply.error("import",e.message,null) else channel.invokeMethod("shareError",e.message) }
            }
        }
    }
}
