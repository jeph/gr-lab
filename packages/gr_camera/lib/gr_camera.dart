/// The camera layer of GR Lab: the only code that talks to Ricoh GR cameras
/// or to the phone's Bluetooth and Wi-Fi on their behalf. Every exchange is
/// reported to the environment's `TraceSink`.
///
/// The app builds one [GrCameraEnvironment] and creates sessions, pairing
/// runs and scanners from it; it never touches protocol objects itself.
library;

import 'package:gr_camera/gr_camera.dart' show GrCameraEnvironment;
import 'package:gr_camera/src/environment.dart' show GrCameraEnvironment;

export 'package:gr_protocol/gr_protocol.dart'
    show
        BleAdapterState,
        BleCaptureStatus,
        BleDriveMode,
        BleEnumValue,
        BleErrorCode,
        BleException,
        BleExposureMode,
        BleShootingMode,
        BleUserMode,
        GrBatteryChange,
        GrCameraChange,
        GrCameraDirectChange,
        GrCaptureChange,
        GrChangeEvent,
        GrImageSize,
        GrLensChange,
        GrModel,
        GrPairedCamera,
        GrPairingException,
        GrPairingFailure,
        GrPairingStage,
        GrPhotoPath,
        GrProps,
        GrSessionEvent,
        GrSessionException,
        GrSessionOptions,
        GrSessionPhase,
        GrSetting,
        GrStorageChange,
        GrStorageId,
        GrStorageInfo,
        GrTransferChange,
        GrUnknownChange,
        GrUnparsedChange,
        JpegDimensions,
        LiveViewFrame,
        TraceChannel,
        TraceDirection,
        TraceEvent,
        TraceSink,
        stripRicohPrefix;

export 'src/environment.dart' show GrCameraEnvironment;
export 'src/library/camera_file.dart' show CameraFile, FileInfo;
export 'src/library/camera_images.dart'
    show CameraImages, ImageRequest, NotAnImageException;
export 'src/library/camera_library.dart'
    show
        CameraLibrary,
        TransferConnectionLost,
        TransferCutOff,
        TransferFailure,
        TransferHttpStatus,
        TransferOtherError,
        TransferRefused,
        TransferStalled,
        TransferWriteFailed,
        isConnectionError;
export 'src/library/listing_cache.dart'
    show CachedListing, readCachedListing, writeCachedListing;
export 'src/library/movie_cache.dart'
    show MovieCache, MovieDownload, MovieDownloadCancelled;
export 'src/library/request_queue.dart'
    show
        QueuedRequest,
        RequestCancelled,
        RequestQueue,
        RequestSignal,
        RequestTicket,
        SharedRequests;
export 'src/nearby.dart' show NearbyCamera, NearbyScanner;
export 'src/pairing.dart' show PairingRun, pairedDeviceName;
export 'src/presence.dart' show CameraSighting, PresenceScanner;
export 'src/session.dart' show CameraSession, WifiConsent;
export 'src/shoot/live_view.dart' show CameraLiveView, FocusMark, FocusState;
export 'src/shoot/remote.dart' show CameraRemote;
