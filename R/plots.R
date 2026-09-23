save_plot <- function(filename, expr, ...) {
  png(file.path(paths$figures, filename), ...)
  on.exit(dev.off())
  expr
}

# Example usage:
# save_plot("MackCL Development Pattern.png", plot(mack$model))
# save_plot("MackCL Triangle.png", plot(tri_mack))