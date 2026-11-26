package app.ufuq.desktop.island

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.PathParser
import androidx.compose.ui.unit.dp

// TODO: duplicated from :app (app.ufuq.android.island.IslandIcons); extract to a KMP :island-ui module later.

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

    private fun build(icon: IslandIcon): ImageVector = when (icon) {
        IslandIcon.SUN -> stroke(
            "sun",
            "M12 8a4 4 0 1 0 0 8a4 4 0 1 0 0-8",
            "M12 2v2 M12 20v2 M4.9 4.9l1.4 1.4 M17.7 17.7l1.4 1.4 M2 12h2 M20 12h2",
        )
        IslandIcon.BELL -> stroke("bell", "M6 8a6 6 0 0 1 12 0c0 7 3 9 3 9H3s3-2 3-9 M10 21h4")
        IslandIcon.REFRESH -> stroke("refresh", "M20 12a8 8 0 1 1-2.3-5.7", "M20 4v5h-5")
        // Three sliders: reads as "settings" without a gear's many curves.
        IslandIcon.SETTINGS -> stroke("settings", "M4 7h10 M18 7h2 M4 17h2 M10 17h10", "M16 4v6 M8 14v6")
        IslandIcon.PLAY -> filled("play", "M8 5v14l11-7z")
        IslandIcon.PAUSE -> filled("pause", "M6 5h4v14H6z M14 5h4v14h-4z")
    }
}
