import wave
import numpy as np
import serial

def wav_to_pcm(wave_path):
    with wave.open(wave_path, "rb") as wav:
        num_channels = wav.getnchannels()
        width = wav.getsampwidth()
        num_frames = wav.getnframes()
        raw = wav.readframes(num_frames)

    if(width == 2):
        samples = np.frombuffer(raw, dtype = np.int16)
        samples = samples.reshape(-1, num_channels)
        #convert to mono audio
        mono_pcm = np.mean(samples, axis = 1) #collapse columns
        return mono_pcm
    else:
        print("Unexpected sample width")
        return None

def stream_to_uart(pcm_data):
    ser = serial.Serial("COM5", baudrate = 921600)
    byte_package = pcm_data.astype('<i2').tobytes()
    ser.write(byte_package)
    ser.flush() #waits for all data to send
    ser.close()

#main
wave_path = "wavFiles/filename.wav"
mono_pcm = wav_to_pcm(wave_path)
print("Converted wav file to pcm")
stream_to_uart(mono_pcm)
print("Finished streaming to uart")