package com.example.kaydetmail

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * Home-screen widget showing the KAYDET wordmark, the current inbox unread
 * count and up to three recent inbox mail lines. Data is written from Dart
 * by `HomeWidgetService` (lib/services/home_widget_service.dart) via
 * `HomeWidget.saveWidgetData`/`HomeWidget.updateWidget`; [widgetData] here is
 * the same SharedPreferences file the plugin reads/writes on the native
 * side. Tapping anywhere on the widget just opens the app — there are no
 * in-widget actions.
 */
class MailWidgetProvider : HomeWidgetProvider() {

  override fun onUpdate(
      context: Context,
      appWidgetManager: AppWidgetManager,
      appWidgetIds: IntArray,
      widgetData: SharedPreferences,
  ) {
    appWidgetIds.forEach { widgetId ->
      val views =
          RemoteViews(context.packageName, R.layout.mail_widget).apply {
            val pendingIntent =
                HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java)
            setOnClickPendingIntent(R.id.mail_widget_root, pendingIntent)

            val unreadCount = widgetData.getInt(UNREAD_COUNT_KEY, 0)
            setTextViewText(R.id.mail_widget_unread_count, "$unreadCount okunmamış")

            bindLine(this, widgetData, R.id.mail_widget_line_1, MAIL_LINE_1_KEY)
            bindLine(this, widgetData, R.id.mail_widget_line_2, MAIL_LINE_2_KEY)
            bindLine(this, widgetData, R.id.mail_widget_line_3, MAIL_LINE_3_KEY)
          }

      appWidgetManager.updateAppWidget(widgetId, views)
    }
  }

  private fun bindLine(
      views: RemoteViews,
      widgetData: SharedPreferences,
      viewId: Int,
      key: String,
  ) {
    val line = widgetData.getString(key, null)
    if (line.isNullOrEmpty()) {
      views.setViewVisibility(viewId, android.view.View.GONE)
    } else {
      views.setViewVisibility(viewId, android.view.View.VISIBLE)
      views.setTextViewText(viewId, line)
    }
  }

  companion object {
    /** Keys mirrored in `HomeWidgetService` — must stay in sync with Dart. */
    const val UNREAD_COUNT_KEY = "kaydet_widget_unread_count"
    const val MAIL_LINE_1_KEY = "kaydet_widget_mail_1"
    const val MAIL_LINE_2_KEY = "kaydet_widget_mail_2"
    const val MAIL_LINE_3_KEY = "kaydet_widget_mail_3"
  }
}
