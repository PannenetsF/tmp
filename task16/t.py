import os
import yaml
starts = '/data/fanyunqian/sch/distkv/lightllm/evaluation/task12/prefill_pred_2instance_' 
base_dir = '/data/fanyunqian/sch/distkv/lightllm/evaluation/task12/'
for fn in os.listdir(base_dir):
    if fn.startswith('prefill_pred_2instance_'):
        # cp it from 2instance to 4instance and 6instance 
        for i in range(1, 7):
            new_fn = fn.replace('2instance', f'{i}instance')
            os.system('cp %s %s' % (base_dir + fn, base_dir + new_fn))
            yaml_data = None 
            with open(base_dir + new_fn, 'r') as f:
                yaml_data = yaml.load(f, Loader=yaml.FullLoader)
            yaml_data['config']['total_instance'] = i
            yaml_data['config']['disabled'] = True
            yaml_data['config']['dump_path'] = '/data/fanyunqian/sch/distkv/lightllm/evaluation/task12/prefill_history.json'
            with open(base_dir + new_fn, 'w') as f:
                yaml.dump(yaml_data, f)

        
starts = '/data/fanyunqian/sch/distkv/lightllm/evaluation/task12/decode_pred_2instance_' 
base_dir = '/data/fanyunqian/sch/distkv/lightllm/evaluation/task12/'
for fn in os.listdir(base_dir):
    if fn.startswith('decode_pred_2instance_'):
        for i in range(1, 7):
            new_fn = fn.replace('2instance', f'{i}instance')
            os.system('cp %s %s' % (base_dir + fn, base_dir + new_fn))
            yaml_data = None 
            with open(base_dir + new_fn, 'r') as f:
                yaml_data = yaml.load(f, Loader=yaml.FullLoader)
            yaml_data['config']['total_instance'] = i
            yaml_data['config']['disabled'] = True
            yaml_data['config']['dump_path'] = '/data/fanyunqian/sch/distkv/lightllm/evaluation/task12/decode_history.json'
            with open(base_dir + new_fn, 'w') as f:
                yaml.dump(yaml_data, f)