package com.music.spotui.ui.immersive.lyrics

import android.content.Context
import android.graphics.Bitmap
import android.graphics.SurfaceTexture
import android.opengl.EGL14.*
import android.opengl.EGLConfig
import android.opengl.EGLSurface
import android.opengl.GLES20.*
import android.opengl.GLUtils
import android.os.Handler
import android.os.HandlerThread
import android.view.TextureView
import app.myspoti.engine.R
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.atomic.AtomicBoolean

/**
 * TextureView participates in the Compose window's transforms, unlike a separate SurfaceView
 * window.
 */
internal class WarpTexture(context: Context, private val unavailable: () -> Unit) :
    TextureView(context), TextureView.SurfaceTextureListener {
    private val thread = HandlerThread("Celestify artwork").apply { start() }
    private val worker = Handler(thread.looper)
    private val busy = AtomicBoolean()
    private var closed = false
    private var renderer: WarpGl? = null // confined to worker
    private var artwork: Bitmap? = null
    private var widthPx = 1
    private var heightPx = 1
    private var clock = 0f
    private var fade = 1f
    private var previous: Bitmap? = null
    private var revision = 0L

    init {
        surfaceTextureListener = this
        isClickable = false
        isFocusable = false
    }

    fun display(bitmap: Bitmap, time: Float, blend: Float) {
        if (artwork !== bitmap) {
            previous = artwork
            artwork = bitmap
        }
        clock = time
        fade = blend
        revision++
        drawFrame()
    }

    private fun drawFrame() {
        val image = artwork ?: return
        if (closed || !isAvailable || !busy.compareAndSet(false, true)) return
        val from = previous ?: image
        val t = clock
        val mix = fade
        val w = widthPx
        val h = heightPx
        val current = revision
        worker.post {
            try {
                renderer?.draw(from, image, t, mix, w, h)
            } catch (e: RuntimeException) {
                fail(e)
            } finally {
                busy.set(false)
                post { if (revision != current) drawFrame() }
            }
        }
    }

    private fun fail(error: RuntimeException) {
        android.util.Log.w("CelestifyArtwork", "Native shader unavailable", error)
        post { if (!closed) unavailable() }
    }

    override fun onSurfaceTextureAvailable(surface: SurfaceTexture, w: Int, h: Int) {
        onSurfaceTextureSizeChanged(surface, w, h)
        worker.post {
            try {
                renderer = WarpGl()
                renderer!!.open(surface, context)
            } catch (e: RuntimeException) {
                fail(e)
            }
            post { drawFrame() }
        }
    }

    override fun onSurfaceTextureSizeChanged(surface: SurfaceTexture, w: Int, h: Int) {
        // The source is already blurred. Keep fragment work proportional on high-density tablets.
        val scale = minOf(1f, 960f / maxOf(1, w, h))
        widthPx = (w * scale).toInt().coerceAtLeast(1)
        heightPx = (h * scale).toInt().coerceAtLeast(1)
        surface.setDefaultBufferSize(widthPx, heightPx)
        drawFrame()
    }

    override fun onSurfaceTextureUpdated(surface: SurfaceTexture) {}

    override fun onSurfaceTextureDestroyed(surface: SurfaceTexture): Boolean {
        if (closed) return true
        worker.post {
            renderer?.close()
            renderer = null
            surface.release()
        }
        return false
    }

    fun release() {
        closed = true
        worker.post {
            renderer?.close()
            renderer = null
            thread.quitSafely()
        }
    }
}

private class WarpGl {
    private var display = EGL_NO_DISPLAY
    private var context = EGL_NO_CONTEXT
    private var surface: EGLSurface = EGL_NO_SURFACE
    private var program = 0
    private val textures = IntArray(2)
    private val loaded = arrayOfNulls<Bitmap>(2)
    private val quad =
        ByteBuffer.allocateDirect(32).order(ByteOrder.nativeOrder()).asFloatBuffer().apply {
            put(floatArrayOf(-1f, -1f, 1f, -1f, -1f, 1f, 1f, 1f))
            position(0)
        }
    private var timeLoc = 0
    private var fadeLoc = 0
    private var resolution = 0
    private val bufferSize = IntArray(2)

    fun open(window: SurfaceTexture, host: Context) {
        display = eglGetDisplay(EGL_DEFAULT_DISPLAY)
        check(eglInitialize(display, IntArray(1), 0, IntArray(1), 0))
        val configs = arrayOfNulls<EGLConfig>(1)
        val attrs =
            intArrayOf(
                EGL_RENDERABLE_TYPE,
                EGL_OPENGL_ES2_BIT,
                EGL_SURFACE_TYPE,
                EGL_WINDOW_BIT,
                EGL_RED_SIZE,
                8,
                EGL_GREEN_SIZE,
                8,
                EGL_BLUE_SIZE,
                8,
                EGL_NONE,
            )
        check(
            eglChooseConfig(display, attrs, 0, configs, 0, 1, IntArray(1), 0) && configs[0] != null
        )
        context =
            eglCreateContext(
                display,
                configs[0],
                EGL_NO_CONTEXT,
                intArrayOf(EGL_CONTEXT_CLIENT_VERSION, 2, EGL_NONE),
                0,
            )
        surface = eglCreateWindowSurface(display, configs[0], window, intArrayOf(EGL_NONE), 0)
        check(eglMakeCurrent(display, surface, surface, context))
        val vertex =
            "attribute vec2 pos; varying vec2 v_texCoord; void main(){gl_Position=vec4(pos,0.,1.); v_texCoord=vec2(pos.x,-pos.y)*.5+.5;}"
        val fragment =
            host.resources.openRawResource(R.raw.spicy_warp).bufferedReader().use { it.readText() }
        program = glCreateProgram()
        for ((type, src) in listOf(GL_VERTEX_SHADER to vertex, GL_FRAGMENT_SHADER to fragment)) {
            val shader = glCreateShader(type)
            glShaderSource(shader, src)
            glCompileShader(shader)
            val status = IntArray(1)
            glGetShaderiv(shader, GL_COMPILE_STATUS, status, 0)
            check(status[0] != 0) { glGetShaderInfoLog(shader) }
            glAttachShader(program, shader)
            glDeleteShader(shader)
        }
        glLinkProgram(program)
        val linked = IntArray(1)
        glGetProgramiv(program, GL_LINK_STATUS, linked, 0)
        check(linked[0] != 0) { glGetProgramInfoLog(program) }
        glUseProgram(program)
        val pos = glGetAttribLocation(program, "pos")
        glEnableVertexAttribArray(pos)
        glVertexAttribPointer(pos, 2, GL_FLOAT, false, 0, quad)
        timeLoc = glGetUniformLocation(program, "u_time")
        fadeLoc = glGetUniformLocation(program, "u_blend")
        resolution = glGetUniformLocation(program, "u_resolution")
        glUniform1f(glGetUniformLocation(program, "u_intensity"), 1f)
        glUniform1i(glGetUniformLocation(program, "u_previous"), 0)
        glUniform1i(glGetUniformLocation(program, "u_texture"), 1)
        glGenTextures(2, textures, 0)
    }

    fun draw(from: Bitmap, to: Bitmap, time: Float, mix: Float, w: Int, h: Int) {
        for (slot in 0..1) {
            val bitmap = if (slot == 0) from else to
            glActiveTexture(GL_TEXTURE0 + slot)
            glBindTexture(GL_TEXTURE_2D, textures[slot])
            if (loaded[slot] !== bitmap) {
                glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR)
                glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR)
                glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE)
                glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE)
                GLUtils.texImage2D(GL_TEXTURE_2D, 0, bitmap, 0)
                loaded[slot] = bitmap
            }
        }
        eglQuerySurface(display, surface, EGL_WIDTH, bufferSize, 0)
        eglQuerySurface(display, surface, EGL_HEIGHT, bufferSize, 1)
        glViewport(0, 0, bufferSize[0], bufferSize[1])
        glUniform2f(resolution, w.toFloat(), h.toFloat())
        glUniform1f(timeLoc, time)
        glUniform1f(fadeLoc, mix)
        glDrawArrays(GL_TRIANGLE_STRIP, 0, 4)
        check(eglSwapBuffers(display, surface))
    }

    fun close() {
        if (display == EGL_NO_DISPLAY) return
        eglMakeCurrent(display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT)
        if (surface != EGL_NO_SURFACE) eglDestroySurface(display, surface)
        if (context != EGL_NO_CONTEXT) eglDestroyContext(display, context)
        eglReleaseThread()
        eglTerminate(display)
    }
}
