#!/usr/bin/python

from scapy.all import *
from scapy.contrib.mpls import MPLS
import argparse
from datetime import datetime


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('-i', '--iface', required=True, help='Infterface to capture')
    parser.add_argument('-f', '--filter', help='Filter use BPF syntax')
    parser.add_argument('-a', '--all', action='store_true', help='Show all content of packet')
    parser.add_argument('-m', '--mpls', nargs='*', help='Filter by inner mpls labels')
    parser.add_argument('--mac', nargs='*', help='Filter by inner mac address')
    parser.add_argument('--ip', nargs='*', help='Filter by inner ip address')
    parser.add_argument('-e', '--hex', action='store_true', help='Dump hex string')
    parser.set_defaults(func=cmd_parser)
    args = parser.parse_args()
    args.func(args)

def cmd_parser(args):
    #print(args)
    cap = Capture()
    if args.mpls:
        cap.filters['label'] = args.mpls
    if args.mac:
        cap.filters['mac'] = args.mac
    if args.ip:
        cap.filters['ip'] = args.ip
    cap.all = args.all
    cap.hex = args.hex
    cap.capture(args.iface, args.filter)

class Capture(object):
    def __init__(self):
        self.filters = {}
        self.all = None
        self.hex = None

    def capture(self, iface, filter=None):
        conf.use_pcap = True
        #conf.L3socket=L3pcapSocket  # Receive/send L3 packets through libpcap
        #conf.L2listen=L2ListenTcpdump  # Receive L2 packets through TCPDump
        sniff(iface=iface, filter=filter, prn=self.dump)

    def custom_filter(self, packet):
        labels = self.filters.get('label')
        macs = self.filters.get('mac')
        ips = self.filters.get('ip')
        mplspkt = packet.getlayer(MPLS)
        if mplspkt:
            if labels and str(mplspkt.label) in labels:
                return True 
            inner_eth = mplspkt.getlayer(Ether)
            if inner_eth and macs and (str(inner_eth.src) in macs or str(inner_eth.dst) in macs):
                return True
            inner_ip = mplspkt.getlayer(IP)
            if inner_ip and ips and (str(inner_ip.src) in ips or str(inner_ip.dst) in ips):
                return True
        if not labels and not macs and not ips:
            return True
        return False

    def dump_all(self, packet):
        print('%s: %s' % (datetime.fromtimestamp(packet.time).strftime('%H:%M:%S.%f'), packet.summary()))
        print('    %r' % packet)

    def dump_one(self, packet):
        fmt = '{Ether:%Ether.src%=>%Ether.dst% | %type%:} {IP:%-15s,IP.src% -> %-15s,IP.dst% %IP.proto%, frag=%IP.frag%, len=%IP.len%, ttl=%IP.ttl%}'
        info = packet.sprintf(fmt)
        print('%s: %s' % (datetime.fromtimestamp(packet.time).strftime('%H:%M:%S.%f'), info))
        info = packet.summary()
        print('    %s' % info)
        mplspkt = packet.getlayer(MPLS)
        if mplspkt:
            info = '    Lable: %s' % mplspkt.label
            inner_eth = mplspkt.getlayer(Ether)
            if inner_eth:
                info = info + ' | %s -> %s' % (inner_eth.src, inner_eth.dst)
            inner_ip = mplspkt.getlayer(IP)
            if inner_ip:
                info = info + ' | IP: frag=%s, checksum=0x%0x' % (inner_ip.frag, inner_ip.chksum)
            inner_tcp = mplspkt.getlayer(TCP)
            if inner_tcp:
                info = info + ' | TCP: seq=%s, ack=%s' % (inner_tcp.seq, inner_tcp.ack)
            print info

    def dump(self, packet):
        #import pdb;pdb.set_trace()
        if not self.custom_filter(packet):
            return
        if self.all:
            self.dump_all(packet)
        else:
            self.dump_one(packet)
        if self.hex:
            hexdump(packet)
        print('')

if __name__ == '__main__':
    main()
