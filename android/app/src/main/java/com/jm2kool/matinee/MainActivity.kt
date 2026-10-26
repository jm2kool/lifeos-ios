package com.jm2kool.matinee

import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.lifecycle.lifecycleScope
import com.jm2kool.matinee.data.Demo
import com.jm2kool.matinee.data.Taste
import kotlinx.coroutines.launch
import com.jm2kool.matinee.ui.Haptics
import com.jm2kool.matinee.ui.MatineeTheme
import com.jm2kool.matinee.ui.RootView
import com.jm2kool.matinee.ui.Router
import kotlin.math.sqrt

class MainActivity : ComponentActivity(), SensorEventListener {
    private var sensors: SensorManager? = null
    private var lastShake = 0L

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge(
            statusBarStyle = SystemBarStyle.dark(android.graphics.Color.TRANSPARENT),
            navigationBarStyle = SystemBarStyle.dark(android.graphics.Color.BLACK),
        )
        Haptics.view = window.decorView
        sensors = getSystemService(SENSOR_SERVICE) as? SensorManager
        if (savedInstanceState != null) Router.showSplash = false
        setContent { MatineeTheme { RootView() } }
        lifecycleScope.launch { Demo.run(intent) }
    }

    override fun onResume() {
        super.onResume()
        sensors?.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)?.let { sensors?.registerListener(this, it, SensorManager.SENSOR_DELAY_UI) }
    }

    override fun onPause() {
        super.onPause()
        sensors?.unregisterListener(this)
    }

    /// Shake for a deck of random picks from your watchlist — anywhere except over the splash, the quiz and sheets.
    override fun onSensorChanged(e: SensorEvent) {
        val (x, y, z) = Triple(e.values[0], e.values[1], e.values[2])
        val g = sqrt(x * x + y * y + z * z) / SensorManager.GRAVITY_EARTH
        val now = System.currentTimeMillis()
        if (g > 2.6f && now - lastShake > 1200) {
            lastShake = now
            if (!Router.showSplash && !Taste.showQuiz && Router.sheet == null && Router.trailer == null) Router.pickRandom()
        }
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
}
