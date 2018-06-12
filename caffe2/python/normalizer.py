# @package optimizer
# Module caffe2.python.optimizer
from __future__ import absolute_import, division, print_function, unicode_literals


class Normalizer(object):
    def __init__(self):
        pass
    """
    Adds normalization to train_net for given parameter. Its factor ahead of
    regularization is given when initialization.
    The param should be a BlobReference.
    """

    def __call__(self, net, param):
        return self._run(net, param)

    def _run(self, net, param):
        raise Exception("Not Impelemented")


class BatchNormalizer(Normalizer):
    def __init__(self, momentum):
        super(BatchNormalizer, self).__init__()
        self._momentum = momentum

    def _run(self, net, param):
        return net.BatchNormalization(
            param, momentum=self._momentum
        )
