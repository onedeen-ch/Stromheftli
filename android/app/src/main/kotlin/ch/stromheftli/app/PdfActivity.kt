package ch.stromheftli.app

import android.app.Activity
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.pdf.PdfRenderer
import android.os.Bundle
import android.os.ParcelFileDescriptor
import android.widget.*
import java.io.File

class PdfActivity : Activity() {
    private var renderer: PdfRenderer? = null
    private var descriptor: ParcelFileDescriptor? = null
    private var number = 0
    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        try {
            val file = File(intent.getStringExtra("path") ?: error("Datei fehlt"))
            descriptor = ParcelFileDescriptor.open(file,ParcelFileDescriptor.MODE_READ_ONLY)
            val doc = PdfRenderer(descriptor!!)
            renderer = doc
            number = (state?.getInt("page") ?: 0).coerceIn(0,doc.pageCount-1)
            val root = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setBackgroundColor(Color.WHITE) }
            val image = ImageView(this).apply { contentDescription = "Rechnungsseite"; scaleType = ImageView.ScaleType.FIT_CENTER }
            root.addView(image, LinearLayout.LayoutParams(-1,0,1f))
            val controls = LinearLayout(this)
            val prev = Button(this).apply { text = "Zurück" }
            val next = Button(this).apply { text = "Weiter" }
            val label = TextView(this).apply { setTextColor(Color.BLACK) }
            controls.addView(prev); controls.addView(label); controls.addView(next); root.addView(controls)
            setContentView(root)
            fun render() {
                doc.openPage(number).use { page ->
                    val scale = minOf(1800f/page.width,2400f/page.height)
                    val bitmap = Bitmap.createBitmap(maxOf(1,(page.width*scale).toInt()),maxOf(1,(page.height*scale).toInt()),Bitmap.Config.ARGB_8888)
                    bitmap.eraseColor(Color.WHITE)
                    page.render(bitmap,null,null,PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                    image.setImageBitmap(bitmap)
                }
                label.text = "  ${number+1} / ${doc.pageCount}  "
                prev.isEnabled = number > 0; next.isEnabled = number+1 < doc.pageCount
            }
            prev.setOnClickListener { number--; render() }; next.setOnClickListener { number++; render() }; render()
        } catch(e: Exception) { Toast.makeText(this,"PDF kann nicht geöffnet werden",Toast.LENGTH_LONG).show(); finish() }
    }
    override fun onSaveInstanceState(state: Bundle) { super.onSaveInstanceState(state); state.putInt("page",number) }
    override fun onDestroy() { renderer?.close(); descriptor?.close(); super.onDestroy() }
}
