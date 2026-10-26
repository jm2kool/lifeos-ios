package com.jm2kool.matinee

import android.app.Application
import com.jm2kool.matinee.data.Catalog
import com.jm2kool.matinee.data.Images
import com.jm2kool.matinee.data.Taste
import com.jm2kool.matinee.model.Library
import com.jm2kool.matinee.model.Prefs

class MatineeApp : Application() {
    override fun onCreate() {
        super.onCreate()
        Prefs.init(this)
        Catalog.init(this)
        Images.init(this)
        Library.init(this)
        Taste.load()
    }
}
