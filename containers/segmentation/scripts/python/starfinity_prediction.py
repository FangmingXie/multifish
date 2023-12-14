#!/usr/bin/env python

import numpy as np
from tifffile import imsave
from csbdeep.utils import normalize
from stardist.models import StarDist3D
import argparse, sys, z5py


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='')
    parser.add_argument('-i','--input', type=str, help='z5 input directory')
    parser.add_argument('-m','--model', type=str, help='model directory')
    parser.add_argument('-o','--output', type=str, help='output file')
    parser.add_argument('-c','--channel', type=str, help='channel')
    parser.add_argument('-s','--scale', type=str, help='scale')
    parser.add_argument('--tile-size', dest='tile_size',
                        type=int, default=128, help='tile_size')

    args = parser.parse_args()

    img_subpath = '/' + args.channel + '/' + args.scale
    print('reading ...', args.input, img_subpath, flush=True)
    img_container = z5py.File(args.input, use_zarr_format=False)
    img = img_container[img_subpath][:, :, :]

    n_tiles = tuple(int(np.ceil(s/args.tile_size)) for s in img.shape)
    print('estimated tiling', img.shape, ' -> ', n_tiles, flush=True)

    print('normalizing input...', flush=True)
    img_normed = normalize(img, 4, 99.8)
    
    model = StarDist3D(None, name=args.model, basedir=args.model)

    print('predicting...', flush=True)
    # the affinity based labels 
    label_starfinity, res_dict = model.predict_instances(img_normed,
                                                         n_tiles=n_tiles,
                                                         affinity=True,
                                                         affinity_thresh=0.1,
                                                         verbose=True)

    # the normal stardist labels are implicitly calculated and
    # can be accessed from the results dict
    label_stardist = res_dict['markers']

    print('saving to ', args.output, ' ...', flush=True)
    
    imsave(args.output, label_starfinity)
    
    print('done', flush=True)
