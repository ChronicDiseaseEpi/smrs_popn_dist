library(RDP)
library(tidyverse)
a <- rbeta(200, 0.5, 0.5)

b <- ecdf(a)
x <- seq(0, 1, 1/(200-1))
d <- quantile(a, probs = x)
e <- RamerDouglasPeucker(d, x, epsilon = 0.01)

f <- approx(x = e$y, y = e$x, xout = x)
f <- as.data.frame(f)
f <- f[,2:1]
names(f) <- c("x", "y")

par(mfrow = c(2,2))
hist(a, main = "1. Original data")
plot(d, x, main = "2. ECDF with RDP in blue", cex = 0.75)
# points(e$x, e$y, col = "blue", main = nrow(e), pch = 12, cex = 1.5)
lines(e$x, e$y, col = "blue", main = nrow(e), cex = 1.25)
hist(f$x, main = "4. Reconstructed data using linear interpolation")
plot(f$x, f$y, main = "3. Reconstructed ECDG via linear interpolation")
