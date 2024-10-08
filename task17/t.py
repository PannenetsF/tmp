import os
import yaml
starts = 'prefill_pred_2instance_' 
base_dir = './'
for fn in os.listdir(base_dir):
    if fn.startswith('prefill_pred_2instance_'):
        # cp it from 2instance to 4instance and 6instance 
        for i in range(1, 25):
            new_fn = fn.replace('2instance', f'{i}instance')
            if i not in [2, 4, 8, 16, 24]:
                os.system(f'rm {base_dir + new_fn}')
                continue
            else:
                os.system('cp %s %s' % (base_dir + fn, base_dir + new_fn))
            yaml_data = None 
            with open(base_dir + new_fn, 'r') as f:
                yaml_data = yaml.load(f, Loader=yaml.FullLoader)
            yaml_data['config']['total_instance'] = i
            yaml_data['config']['disabled'] = True
            yaml_data['config']['dump_path'] = '/data/fanyunqian/ela-1004/ela-1004distkv/lightllm/evaluation/task13/prefill_history.json'
            with open(base_dir + new_fn, 'w') as f:
                yaml.dump(yaml_data, f)

        
starts = 'decode_pred_2instance_' 
base_dir = './'
for fn in os.listdir(base_dir):
    if fn.startswith('decode_pred_2instance_'):
        for i in range(1, 25):
            new_fn = fn.replace('2instance', f'{i}instance')
            if i not in [2, 4, 8, 16, 24]:
                os.system(f'rm {base_dir + new_fn}')
                continue
            else:
                os.system('cp %s %s' % (base_dir + fn, base_dir + new_fn))
            yaml_data = None 
            with open(base_dir + new_fn, 'r') as f:
                yaml_data = yaml.load(f, Loader=yaml.FullLoader)
            yaml_data['config']['total_instance'] = i
            yaml_data['config']['disabled'] = True
            yaml_data['config']['dump_path'] = '/data/fanyunqian/ela-1004/ela-1004distkv/lightllm/evaluation/task13/decode_history.json'
            with open(base_dir + new_fn, 'w') as f:
                yaml.dump(yaml_data, f)
