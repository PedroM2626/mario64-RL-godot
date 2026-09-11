# Correção de Compatibilidade Stable-Baselines3

## Problema
O `stable-baselines3==2.4.1` tem um bug de compatibilidade com `gymnasium>=1.0.0`. 
O erro ocorre no arquivo:
```
.venv311\Lib\site-packages\stable_baselines3\common\vec_env\vec_video_recorder.py
```

Tentando importar:
```python
from gymnasium.wrappers.monitoring import video_recorder
```

Que não existe mais no gymnasium 1.0.0 (a API mudou para usar `RecordVideo`).

## Solução Aplicada
Comentar a importação problemática do `VecVideoRecorder` no arquivo:
```
.venv311\Lib\site-packages\stable_baselines3\common\vec_env\__init__.py
```

Linhas modificadas:
- Linha 14: Importação do VecVideoRecorder comentada
- Linha 100: Removido da lista __all__

## Nota
Esta correção desativa a funcionalidade de gravação de vídeo do VecVideoRecorder, 
mas não afeta o treinamento RL normal. Se precisar de gravação de vídeo, 
use o `RecordVideo` do gymnasium diretamente.

## Versões Compatíveis
- stable-baselines3==2.4.1
- gymnasium==1.0.0
- shimmy==2.0.0
