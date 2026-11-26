package app.ufuq.android.island

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.PathParser
import androidx.compose.ui.unit.dp

/** The island's icons as vectors (the mockup's 24-unit stroke icons), tinted where they are drawn. */
object IslandIcons {
    private val cache = mutableMapOf<IslandIcon, ImageVector>()

    fun of(icon: IslandIcon): ImageVector = cache.getOrPut(icon) { build(icon) }

    private fun stroke(name: String, vararg paths: String): ImageVector =
        ImageVector.Builder(name, 24.dp, 24.dp, 24f, 24f).apply {
            for (d in paths) {
                addPath(
                    pathData = PathParser().parsePathString(d).toNodes(),
                    stroke = SolidColor(Color.White),
                    strokeLineWidth = 2f,
                    strokeLineCap = StrokeCap.Round,
                    strokeLineJoin = StrokeJoin.Round,
                )
            }
        }.build()

    private fun filled(name: String, vararg paths: String): ImageVector =
        ImageVector.Builder(name, 24.dp, 24.dp, 24f, 24f).apply {
            for (d in paths) addPath(pathData = PathParser().parsePathString(d).toNodes(), fill = SolidColor(Color.White))
        }.build()

    private const val BELL = "M6 8a6 6 0 0 1 12 0c0 7 3 9 3 9H3s3-2 3-9 M10 21h4"

    private fun build(icon: IslandIcon): ImageVector = when (icon) {
        IslandIcon.SUN -> stroke(
            "sun",
            "M12 8a4 4 0 1 0 0 8a4 4 0 1 0 0-8",
            "M12 2v2 M12 20v2 M4.9 4.9l1.4 1.4 M17.7 17.7l1.4 1.4 M2 12h2 M20 12h2",
        )
        IslandIcon.BELL -> stroke("bell", BELL)
        IslandIcon.BELL_OFF -> stroke("bell-off", BELL, "M3 3l18 18")
        IslandIcon.REFRESH -> stroke("refresh", "M20 12a8 8 0 1 1-2.3-5.7", "M20 4v5h-5")
        IslandIcon.PHONE -> stroke("phone", "M7 2h10a2 2 0 0 1 2 2v16a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2z", "M10 18h4")
        IslandIcon.PLAY -> filled("play", "M8 5v14l11-7z")
        IslandIcon.PAUSE -> filled("pause", "M6 5h4v14H6z M14 5h4v14h-4z")
    }
}
