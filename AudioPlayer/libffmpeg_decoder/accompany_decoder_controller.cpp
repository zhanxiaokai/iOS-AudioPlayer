#include "accompany_decoder_controller.h"

#define LOG_TAG "AccompanyDecoderController"
AccompanyDecoderController::AccompanyDecoderController() {
	accompanyDecoder = NULL;
	playPosition = 0.0f;
    currentAccompanyPacket = NULL;
    currentAccompanyPacketCursor = 0;
}

AccompanyDecoderController::~AccompanyDecoderController() {
    if(currentAccompanyPacket) {
        delete currentAccompanyPacket;
        currentAccompanyPacket = NULL;
    }
}

int AccompanyDecoderController::getMusicMeta(const char* accompanyPath, int * accompanyMetaData) {
	//获取伴奏的meta
	AccompanyDecoder* accompanyDecoder = new AccompanyDecoder();
	accompanyDecoder->getMusicMeta(accompanyPath, accompanyMetaData);
	delete accompanyDecoder;
	//初始化伴奏的采样率
	accompanySampleRate = accompanyMetaData[0];
//	LOGI("accompanySampleRate is %d", accompanySampleRate);
	return 0;
}

float AccompanyDecoderController::getPlayPosition(){
	return playPosition;
}

float AccompanyDecoderController::seekToPosition(float position){
	LOGI("enter AccompanyDecoderController::seekToPosition() position=%f", position);
	float actualSeekPosition = -1;
	if (NULL != accompanyDecoder) {
		//stop decoder thread
		pthread_mutex_lock(&mDecodePausingLock);
		pthread_mutex_lock(&mLock);
		isDecodePausingFlag = true;
		pthread_cond_signal(&mCondition);
		pthread_mutex_unlock(&mLock);

		pthread_cond_wait(&mDecodePausingCondition, &mDecodePausingLock);
		packetPool->clearDecoderAccompanyPacketToQueue();
		accompanyDecoder->setPosition(position);
		isDecodePausingFlag = false;
		pthread_mutex_unlock(&mDecodePausingLock);

		pthread_mutex_lock(&mLock);
		pthread_cond_signal(&mCondition);
		pthread_mutex_unlock(&mLock);

		while((actualSeekPosition = accompanyDecoder->getActualSeekPosition()) == -1){
			usleep(10 * 1000);
		}

		LOGI("exit AccompanyDecoderController::seekToPosition() position=%f, actualSeekPosition=%f", position, actualSeekPosition);
	}
	return actualSeekPosition;
}

void* AccompanyDecoderController::startDecoderThread(void* ptr) {
	LOGI("enter AccompanyDecoderController::startDecoderThread");
	AccompanyDecoderController* decoderController = (AccompanyDecoderController *) ptr;
	int getLockCode = pthread_mutex_lock(&decoderController->mLock);
	while (decoderController->isRunning) {
		if (decoderController->isDecodePausingFlag) {
			pthread_mutex_lock(&decoderController->mDecodePausingLock);
			pthread_cond_signal(&decoderController->mDecodePausingCondition);
			pthread_mutex_unlock(&decoderController->mDecodePausingLock);

			pthread_cond_wait(&decoderController->mCondition, &decoderController->mLock);
		}
		else {
			decoderController->decodeSongPacket();
			if (decoderController->packetPool->geDecoderAccompanyPacketQueueSize() > QUEUE_SIZE_MAX_THRESHOLD) {
				pthread_cond_wait(&decoderController->mCondition, &decoderController->mLock);
			}
		}
	}
	pthread_mutex_unlock(&decoderController->mLock);
    return 0;
}

void AccompanyDecoderController::initAccompanyDecoder(const char* accompanyPath) {
	//	LOGI("accompanyByteCountPerSec is %d packetBufferTimePercent is %f accompanyPacketBufferSize is %d", accompanyByteCountPerSec, packetBufferTimePercent, accompanyPacketBufferSize);
	//初始化两个decoder
	accompanyDecoder = new AccompanyDecoder();
	accompanyDecoder->init(accompanyPath, accompanyPacketBufferSize);
}

void AccompanyDecoderController::init(const char* accompanyPath, float packetBufferTimePercent) {
	//初始化两个全局变量
	volume = 1.0f;
	accompanyMax = 1.0f;

    int meta[2];
    this->getMusicMeta(accompanyPath, meta);
	//计算计算出伴奏和原唱的bufferSize
	int accompanyByteCountPerSec = accompanySampleRate * CHANNEL_PER_FRAME * BITS_PER_CHANNEL / BITS_PER_BYTE;
	accompanyPacketBufferSize = (int) ((accompanyByteCountPerSec / 2) * packetBufferTimePercent);

//	LOGI("accompanyByteCountPerSec is %d packetBufferTimePercent is %f accompanyPacketBufferSize is %d", accompanyByteCountPerSec, packetBufferTimePercent, accompanyPacketBufferSize);
	//初始化两个decoder
	initAccompanyDecoder(accompanyPath);
	//初始化队列以及开启线程
	packetPool = PacketPool::GetInstance();
	packetPool->initDecoderAccompanyPacketQueue();
	initDecoderThread();
}

void AccompanyDecoderController::initDecoderThread() {
	isRunning = true;
	isDecodePausingFlag = false;
	pthread_mutex_init(&mLock, NULL);
	pthread_cond_init(&mCondition, NULL);
	pthread_mutex_init(&mDecodePausingLock, NULL);
	pthread_cond_init(&mDecodePausingCondition, NULL);
	pthread_create(&songDecoderThread, NULL, startDecoderThread, this);
}

//需要子类完成自己的操作
void AccompanyDecoderController::decodeSongPacket() {
//	LOGI("start AccompanyDecoderController::decodeSongPacket");
//	long readLatestFrameTimemills = getCurrentTime();
	AudioPacket* accompanyPacket = accompanyDecoder->decodePacket();
	accompanyPacket->action = AudioPacket::AUDIO_PACKET_ACTION_PLAY;
	packetPool->pushDecoderAccompanyPacketToQueue(accompanyPacket);
//	LOGI("decode accompany Packet waste time mills is %d", (getCurrentTime() - readLatestFrameTimemills));
}

void AccompanyDecoderController::destroyDecoderThread() {
//	LOGI("enter AccompanyDecoderController::destoryProduceThread ....");
	isRunning = false;
	isDecodePausingFlag = false;
	void* status;
	int getLockCode = pthread_mutex_lock(&mLock);
	pthread_cond_signal (&mCondition);
	pthread_mutex_unlock (&mLock);
	pthread_join(songDecoderThread, &status);
	pthread_mutex_destroy(&mLock);
	pthread_cond_destroy(&mCondition);

	pthread_mutex_lock(&mDecodePausingLock);
	pthread_cond_signal(&mDecodePausingCondition);
	pthread_mutex_unlock(&mDecodePausingLock);
	pthread_mutex_destroy(&mDecodePausingLock);
	pthread_cond_destroy(&mDecodePausingCondition);
}

int AccompanyDecoderController::readSamples(short* samples, int size) {
	int result = -1;
    int fillCuror = 0;
    int sampleCursor = 0;
    while(fillCuror < size) {
        int samplePacketSize = 0;
        if(currentAccompanyPacket && currentAccompanyPacketCursor == currentAccompanyPacket->size) {
            delete currentAccompanyPacket;
            currentAccompanyPacket = NULL;
        }
        if(currentAccompanyPacket && currentAccompanyPacketCursor < currentAccompanyPacket->size) {
            int subSize = size - fillCuror;
            samplePacketSize = MIN(currentAccompanyPacket->size - currentAccompanyPacketCursor, subSize);
            memcpy(samples + fillCuror, currentAccompanyPacket->buffer + currentAccompanyPacketCursor, samplePacketSize * 2);
        } else {
            packetPool->getDecoderAccompanyPacket(&currentAccompanyPacket, true);
            currentAccompanyPacketCursor = 0;
            if (NULL != currentAccompanyPacket && currentAccompanyPacket->size > 0) {
                samplePacketSize = size - fillCuror;
                memcpy(samples + fillCuror, currentAccompanyPacket->buffer + currentAccompanyPacketCursor, samplePacketSize * 2);
            } else {
                result = -2;
                break;
            }
        }
        currentAccompanyPacketCursor += samplePacketSize;
        fillCuror += samplePacketSize;
    }
	
	if(packetPool->geDecoderAccompanyPacketQueueSize() < QUEUE_SIZE_MIN_THRESHOLD){
		pthread_mutex_lock(&mLock);
//        if (result != -1) {
			pthread_cond_signal(&mCondition);
//        }
		pthread_mutex_unlock (&mLock);
	}
	return result;
}

void AccompanyDecoderController::destroy() {
	destroyDecoderThread();
	packetPool->abortDecoderAccompanyPacketQueue();
	packetPool->destoryDecoderAccompanyPacketQueue();
	if (NULL != accompanyDecoder) {
		accompanyDecoder->destroy();
		delete accompanyDecoder;
		accompanyDecoder = NULL;
	}
}
