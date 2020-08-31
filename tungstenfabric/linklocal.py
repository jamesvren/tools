#!/usr/bin/python

import xml.etree.ElementTree as ET
from prettytable import PrettyTable
import os, sys

def get_vm_info(vrouter_ip='localhost'):
    vm_info = PrettyTable()
    vm_info.field_names = ["Compute Node", "VM Name", "VM IP Address", "Link-Local Address"]

    os.popen('curl -s http://' + vrouter_ip + ':8085/Snh_VrouterInfoReq > vrouter_name.xml')
    os.popen('curl -s http://' + vrouter_ip + ':8085/Snh_ItfReq > ' + vrouter_ip + '.xml')

    vrouter_tree = ET.parse('vrouter_name.xml')
    vrouter_root = vrouter_tree.getroot()
    os.remove('vrouter_name.xml')
    vrouter_name = vrouter_root.find('display_name').text
    compute_name = vrouter_name + ' [' + vrouter_ip + ']'

    compute_tree = ET.parse(vrouter_ip + '.xml')
    compute_root = compute_tree.getroot()
    os.remove(vrouter_ip + '.xml')

    for interface in compute_root.iter('ItfSandeshData'):
        vm_name = interface.find('vm_name').text
        ip_addr = interface.find('ip_addr').text
        mdata_ip_addr = interface.find('mdata_ip_addr').text

        if vm_name is not None:
            vm_info.add_row([compute_name, vm_name, ip_addr, mdata_ip_addr])
    return vm_info

def main():
    if len(sys.argv) > 1:
        vrouter_ip = sys.argv[1]
    else:
        vrouter_ip = 'localhost'
    vm_info = get_vm_info(vrouter_ip)
    print(vm_info)

if __name__ == '__main__':
    main()
