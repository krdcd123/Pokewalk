package com.krdcd.pokewalk

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.ContextCompat

class MainActivity : ComponentActivity() {
    private val askSteps = registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        if (granted) Store.startSteps(this)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent { PokeWalkRoot(onStarted = { ensurePermission() }) }
    }

    private fun ensurePermission() {
        if (Build.VERSION.SDK_INT >= 29 &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.ACTIVITY_RECOGNITION) != PackageManager.PERMISSION_GRANTED
        ) {
            askSteps.launch(Manifest.permission.ACTIVITY_RECOGNITION)
        } else {
            Store.startSteps(this)
        }
    }

    override fun onResume() {
        super.onResume()
        if (Store.state.started) ensurePermission()
    }

    override fun onPause() {
        super.onPause()
        Store.stopSteps(this)      // the hardware counter keeps going; we catch up next time
    }
}
