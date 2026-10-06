This file holds Figure 3.1 of companion I, *The mathematics behind the bCCNN*, as native Word shapes. Every box, arrow and the legend line is a separate shape in one group, and the mathematics in the boxes is ordinary text with italics, subscripts and superscripts, so that labels, colours, sizes and positions can be changed in Word. To move a box, select it inside the group and drag it, then move the end points of its arrows; elbow arrows are changed with Edit Points.

QQDRAWING|architecture

QQFIGCAP|3.1|The network of bccnn_model() with the Keras layer names

The green path is the skip connection, which carries the cross-classified over-dispersed Poisson (ccODP) linear predictor unchanged to the output; the orange path is the feed-forward part; the output neuron adds the two on the log scale and exponentiates. Started at $w = 1$, $c = \hat c$ and $B = 0$, the network is exactly the ccODP (chain-ladder) model.
