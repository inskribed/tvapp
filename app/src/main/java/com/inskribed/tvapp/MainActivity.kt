package com.inskribed.tvapp

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.viewModels
import com.inskribed.tvapp.ui.AppRoot
import com.inskribed.tvapp.ui.TvAppTheme

class MainActivity : ComponentActivity() {
    private val vm: AppViewModel by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            TvAppTheme {
                AppRoot(vm)
            }
        }
        DemoHook.run(this, vm) // does nothing in release builds
    }
}
