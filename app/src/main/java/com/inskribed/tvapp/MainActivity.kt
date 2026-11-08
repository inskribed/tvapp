package com.inskribed.tvapp

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.lifecycle.viewmodel.compose.viewModel
import com.inskribed.tvapp.ui.AppRoot
import com.inskribed.tvapp.ui.TvAppTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            TvAppTheme {
                val vm: AppViewModel = viewModel()
                AppRoot(vm)
            }
        }
    }
}
