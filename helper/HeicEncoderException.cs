using System;

namespace PSImageConverter
{
    /// <summary>
    /// The error of the HEIC encoder of the operating system: it is missing, it rejected the image, or
    /// it failed (an error that did not come from the encoder itself is the inner exception).
    /// </summary>
    public sealed class HeicEncoderException : Exception
    {
        /// <summary>
        /// Creates the exception for an encoder that rejected an image.
        /// </summary>
        /// <param name="message">The message that names the encoder call that failed and its error code.</param>
        public HeicEncoderException(string message)
            : this(message, false)
        {
        }

        /// <summary>
        /// Creates the exception and says whether the encoder is missing.
        /// </summary>
        /// <param name="message">The message that names the encoder call that failed and its error code.</param>
        /// <param name="encoderMissing">True when the error means that no HEIC encoder is installed.</param>
        public HeicEncoderException(string message, bool encoderMissing)
            : base(message)
        {
            EncoderMissing = encoderMissing;
        }

        /// <summary>
        /// Creates the exception for an error that did not come from the encoder itself, e.g. a missing
        /// native function or too little memory.
        /// </summary>
        /// <param name="message">The message that names the platform and the error.</param>
        /// <param name="innerException">The original error.</param>
        public HeicEncoderException(string message, Exception innerException)
            : base(message, innerException)
        {
        }

        /// <summary>
        /// Gets a value indicating whether the error means that no HEIC encoder is installed; false when
        /// the encoder exists but rejected this image or failed, or when the error came from elsewhere.
        /// </summary>
        public bool EncoderMissing { get; }
    }
}
