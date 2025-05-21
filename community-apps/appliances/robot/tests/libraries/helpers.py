import re
from urllib.parse import urlparse
from OpenSSL.crypto import (dump_certificate_request, dump_privatekey,
                            PKey, TYPE_RSA, X509Req)
from OpenSSL.SSL import FILETYPE_PEM
import socket
import copy
import pickle
import fcntl
import struct



def parse_url(input):
    return urlparse(input)


def get_db_host(input):
    p = re.compile('^(http|https):\/\/([^:/]+):?([0-9]{1,6})?.*')
    m = p.match(input)
    if m:
        if m.lastindex == 3:
            return m[2], m[3]
        return m[2], 80
    else:
        raise Exception('Host is not present at ' + input)


def get_subscriber_and_subscription_from_location(input):
    p = re.compile('^.*/v1/([a-zA-Z0-9]+)/subscriptions/([a-zA-Z0-9]+)/?')
    m = p.match(input)
    if m:
        if m.lastindex == 2:
            return m[1], m[2]
        raise Exception('Only match ' + m.lastindex + ' and the expected is 2')
    else:
        raise Exception('Host is not present at ' + input)


def get_registration_id(input):
    p = re.compile('^.*/v1/registrations/([a-zA-Z0-9]+)/?')
    m = p.match(input)
    if m:
        if m.lastindex == 1:
            return m[1]
        raise Exception('Only match ' + m.lastindex + ' and the expected is 1')
    else:
        raise Exception('registration id is not present at ' + input)


def store_in_file(file_path, data):
    with open(file_path, 'wb') as f:
        f.write(bytes(data, 'utf-8'))
        f.close()

def read_file_utf8(file_path: str) -> str:
    try:
        with open(file_path, 'r', encoding='utf-8') as file:
            return file.read()
    except Exception as error:
        raise Exception(f"Error al leer el archivo: {error}")

def cert_tuple(cert_file, key_file):
    return (cert_file, key_file)


def add_dns_to_hosts(ip_address, host_name):
    capif_dns = "{}      {}".format(ip_address, host_name)
    dns_file = open("/etc/hosts", "a")
    dns_file.write("{}\n".format(capif_dns))
    dns_file.close()


def get_ip_from_hostname(hostname):
    return socket.gethostbyname(hostname)


def remove_keys_from_object_helper(input, keys_to_remove):
    print(keys_to_remove)
    print(input)
    print(type(input))
    if isinstance(input, list):
        print('list')
        for data in input:
            remove_keys_from_object_helper(data, keys_to_remove)
            return True

    # Check Variable type
    elif isinstance(input, dict):
        print('dict')

        for key in list(input.keys()):
            print('key=' + key)
            if key in keys_to_remove:
                print('Remove ' + key + ' from object')
                del input[key]
            elif isinstance(input[key], dict) or isinstance(input[key], list):
                remove_keys_from_object_helper(input[key], keys_to_remove)
    else:
        return True
    return input


def remove_key_from_object(input, key_to_remove):
    input_copy = copy.deepcopy(input)
    remove_keys_from_object_helper(input_copy, [key_to_remove])
    return input_copy


def add_key_to_object(input, key_to_add, value_to_add):
    input_copy = copy.deepcopy(input)
    input_copy[key_to_add] = value_to_add
    return input_copy


def create_scope(aef_id, api_name):
    data = "3gpp#" + aef_id + ":" + api_name

    return data


def read_dictionary(file_path):
    with open(file_path, 'rb') as fp:
        data = pickle.load(fp)
        print('Dictionary loaded')
        return data


def write_dictionary(file_path, data):
    with open(file_path, 'wb') as fp:
        pickle.dump(data, fp)
        print('dictionary saved successfully to file ' + file_path)


def filter_users_by_prefix_username(users, prefix):
    if prefix.strip() == "":
        raise Exception('prefix value must contain some value')

    filtered_users = list()
    for user in users:
        if user['username'].startswith(prefix):
            filtered_users.append(user['username'])
    return filtered_users


def get_ip_with_mask(ip):
    if '/' not in ip:
        if '.' in ip:
            return ip + '/32';
        elif ':' in ip:
            return ip + '/128';
    return ip;

def ping_command(ip):
    if ':' in ip:
        return 'ping -6';
    return 'ping';


def filter_keys(dictionary, keys_to_store=[]):
    keys = list(dictionary.keys())
    for key in keys:
        if key in keys_to_store:
            print('not removing key ' + key + ' in dictionary file')
            pass
        else:
            print('deleting key ' + key + ' in new dictionary file')
            dictionary.pop(key)
    return dictionary


def get_ip_for_interface(interface_name):
    """
    Return IP associated to interace pass by parameters.
    Returns None if that interface has no IP assigned or not exists.
    """
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        packed_iface = struct.pack('256s', interface_name[:15].encode('utf-8'))
        ip = fcntl.ioctl(sock.fileno(), 0x8915, packed_iface)[20:24]  # SIOCGIFADDR
        return socket.inet_ntoa(ip)
    except OSError:
        return None

