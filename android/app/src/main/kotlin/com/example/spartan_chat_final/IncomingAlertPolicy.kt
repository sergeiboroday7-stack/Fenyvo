package com.example.spartan_chat_final

import android.media.AudioManager

internal data class IncomingAlertPolicy(val sound: Boolean, val vibration: Boolean)

internal fun incomingAlertPolicy(
    ringerMode: Int,
    doNotDisturb: Boolean,
    ringVolume: Int,
): IncomingAlertPolicy {
    if (doNotDisturb || ringerMode == AudioManager.RINGER_MODE_SILENT) {
        return IncomingAlertPolicy(false, false)
    }
    return IncomingAlertPolicy(
        sound = ringerMode == AudioManager.RINGER_MODE_NORMAL && ringVolume > 0,
        vibration = ringerMode == AudioManager.RINGER_MODE_NORMAL ||
            ringerMode == AudioManager.RINGER_MODE_VIBRATE,
    )
}
