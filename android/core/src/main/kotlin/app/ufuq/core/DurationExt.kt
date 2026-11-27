package app.ufuq.core

import java.time.Duration

internal fun Duration.coerceAtLeast(min: Duration): Duration = if (this < min) min else this
