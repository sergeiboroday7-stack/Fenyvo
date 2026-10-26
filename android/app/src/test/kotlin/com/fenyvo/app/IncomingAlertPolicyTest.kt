package com.fenyvo.app

import android.media.AudioManager
import org.junit.Assert.assertEquals
import org.junit.Test

class IncomingAlertPolicyTest {
    @Test fun normalModeAllowsSoundAndVibration() {
        assertEquals(IncomingAlertPolicy(true, true),
            incomingAlertPolicy(AudioManager.RINGER_MODE_NORMAL, false, 5))
    }
    @Test fun vibrateModeNeverPlaysSound() {
        assertEquals(IncomingAlertPolicy(false, true),
            incomingAlertPolicy(AudioManager.RINGER_MODE_VIBRATE, false, 5))
    }
    @Test fun silentModeNeverMakesNoiseOrVibration() {
        assertEquals(IncomingAlertPolicy(false, false),
            incomingAlertPolicy(AudioManager.RINGER_MODE_SILENT, false, 5))
    }
    @Test fun doNotDisturbSuppressesBothInEveryMode() {
        for (mode in listOf(0, 1, 2)) {
            assertEquals(IncomingAlertPolicy(false, false), incomingAlertPolicy(mode, true, 5))
        }
    }
    @Test fun zeroRingVolumeDoesNotPlaySound() {
        assertEquals(IncomingAlertPolicy(false, true),
            incomingAlertPolicy(AudioManager.RINGER_MODE_NORMAL, false, 0))
    }
}
