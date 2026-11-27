package com.inskribed.tvapp

import androidx.activity.ComponentActivity

/** Release builds have no demo mode. (The real one lives in src/debug and is used by the screenshot workflow.) */
@Suppress("UNUSED_PARAMETER")
object DemoHook {
    fun run(activity: ComponentActivity, vm: AppViewModel) {}
}
