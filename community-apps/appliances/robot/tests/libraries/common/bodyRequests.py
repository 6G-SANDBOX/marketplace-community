import re
import json
from xmlrpc.client import boolean
import rfc3987

f = open('/opt/robot-tests/tests/libraries/common/types.json')
capif_types = json.load(f)


def check_variable(input, data_type):
    print(input)
    print(type(input))
    print(data_type)
    if isinstance(input, list):
        for one in input:
            check_variable(one, data_type)
        return True
    if data_type == "string":
        if isinstance(input, str):
            return True
        else:
            raise Exception("variable is not string type")
    elif data_type == "integer":
        if isinstance(input, int):
            return True
        else:
            raise Exception("variable is not integer type")
    elif data_type == "boolean":
        if isinstance(input, boolean):
            return True
        else:
            raise Exception("variable is not integer type")
    elif data_type == "URI":
        check_uri(input, data_type)
        return True
    elif data_type == "URI_reference":
        check_uri(input, data_type)
        return True
    elif data_type not in capif_types.keys():
        raise Exception("ERROR, type " + data_type +
                        " is not present in types file")
    if "Check" in capif_types[data_type].keys():
        if not capif_types[data_type]["Check"]:
            return True
    if "enum" in capif_types[data_type].keys():
        if input in capif_types[data_type]["enum"]:
            print("value (" + input + ") is present at enum (" +
                  ','.join(capif_types[data_type]["enum"]) + ")")
            return True
        else:
            raise Exception("value (" + input + ") is not present at enum (" +
                            ','.join(capif_types[data_type]["enum"]) + ")")
    if "regex" in capif_types[data_type].keys():
        check_regex(input, capif_types[data_type]["regex"])
        return True

    # Check Structure
    all_attributes = check_attributes_dict(input, data_type)

    print(all_attributes)

    print('Check Variable type')
    # Check Variable type
    for key in input.keys():
        print(key)
        check_variable(input[key], all_attributes[key])


def check_attributes_dict(body, data_type):
    mandatory_attributes = capif_types[data_type]["mandatory_attributes"]
    optional_parameters = capif_types[data_type]["optional_attributes"]
    regex_attributes = capif_types[data_type].get("regex_attributes", {})

    all_attributes = mandatory_attributes | optional_parameters
    # Check if body has not allowed attributes

    for body_key in body.keys():
        print(body_key)
        if body_key not in all_attributes.keys():
            print(body_key + " NOT IN ALL ATTRIBUTES")
            present = False
            if regex_attributes is not None:
                print("REGEX ATTRIBUTES PRESENT")
                print(regex_attributes)
                for regex_key, regex_data_type in regex_attributes.items():
                    print(regex_key + ":" + regex_data_type)
                    if check_regex(body_key, regex_key):
                        print("MATCH with " + body_key)
                        present = True
                        all_attributes[body_key] = regex_data_type
                        break
            if not present:
                raise Exception('Attribute "' + body_key +
                                '" is not present as a mandatory or optional key (' + ','.join(all_attributes.keys()) + ')')

    if mandatory_attributes:
        for mandatory_key in mandatory_attributes.keys():
            if mandatory_key not in body.keys():
                raise Exception('Mandatory Attribute "' + mandatory_key +
                                '" is not present at body under check')

    if 'oneOf' in capif_types[data_type].keys():
        one_of = capif_types[data_type]["oneOf"]
        count = 0
        for body_key in body.keys():
            if body_key in one_of:
                count = count+1

        if count == 0:
            raise Exception('Mandatory oneOf [' + ','.join(one_of) +
                            '] is not present at body (' + ','.join(body.keys()) + ')')
        elif count > 1:
            raise Exception('More than one oneOf [' + ','.join(
                one_of) + '] is present at body (' + ','.join(body.keys()) + ')')

    return all_attributes


def check_uri(input, rule):
    if rfc3987.match(input, rule=rule) is not None:
        return input
    else:
        raise Exception(rule + " is not accomplish rfc3986 rule ("+input+")")


def check_regex(input, regex):
    matched = re.match(regex, input)
    is_match = bool(matched)
    if is_match:
        print("Regex match")
        return True
    else:
        raise Exception("Input(" + input + ") not match regex (" + regex + ")")
