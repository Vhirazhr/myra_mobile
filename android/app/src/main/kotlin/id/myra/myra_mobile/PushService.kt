package id.myra.myra_mobile

import android.app.*
import android.content.Context
import android.content.Intent
import android.os.Build
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

class PushService : FirebaseMessagingService() {
    override fun onMessageReceived(message: RemoteMessage) {
        val notice = message.data["notification_id"] ?: return
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel = "myra_messages"
        if (Build.VERSION.SDK_INT >= 26) manager.createNotificationChannel(NotificationChannel(channel,"Pesan MYRA",NotificationManager.IMPORTANCE_DEFAULT))
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this,channel) else Notification.Builder(this)
        val intent = Intent(this,MainActivity::class.java).setFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP).putExtra("notification_id",notice)
        val tap = PendingIntent.getActivity(this,notice.hashCode(),intent,PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        builder.setSmallIcon(android.R.drawable.ic_dialog_email).setContentTitle(message.notification?.title ?: "MYRA")
            .setContentText(message.notification?.body).setContentIntent(tap).setAutoCancel(true)
        if (Build.VERSION.SDK_INT < 33 || checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) == android.content.pm.PackageManager.PERMISSION_GRANTED) manager.notify(notice.hashCode(),builder.build())
    }
}
