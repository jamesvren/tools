#!/usr/bin/python

from scapy.all import *
from scapy.contrib.mpls import MPLS
import argparse
from datetime import datetime


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('-i', '--iface', required=True, help='Infterface to capture')
    parser.add_argument('-f', '--filter', help='Filter use BPF syntax')
    parser.set_defaults(func=cmd_parser)
    args = parser.parse_args()
    args.func(args)

def cmd_parser(args):
    filter = None
    iface = args.iface
    if args.filter:
        filter = args.filter
    capture(iface, filter)

def capture(iface, filter=None):
    sniff(iface=iface, filter=filter, prn=dump)

def dump(packet):
    #import pdb;pdb.set_trace()
    #packet.show()
    fmt = '{Ether:%Ether.src%=>%Ether.dst%, %type%:} {IP:%-15s,IP.src% -> %-15s,IP.dst%, %IP.proto%, len=%IP.len%, ttl=%IP.ttl%}'
    print('%s: %s' % (datetime.fromtimestamp(packet.time).strftime('%H:%M:%S.%f'), packet.sprintf(fmt)))
    print('    %s' % packet.summary())
    mplspkt = packet.getlayer(MPLS)
    if mplspkt:
        info = '    Lable: %s' % mplspkt.label
        inner_eth = mplspkt.getlayer(Ether)
        if inner_eth:
            info = info + ' | %s -> %s' % (inner_eth.src, inner_eth.dst)
        print info
    print('\n')

if __name__ == '__main__':
    main()
