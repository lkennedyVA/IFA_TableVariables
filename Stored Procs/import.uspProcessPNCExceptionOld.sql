USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspProcessPNCException
	CreatedBy: Larry Dugger
	Date: 2017-08-18
	Description: This procedure will process all of the unprocessed records

	Tables: [import].[File]
		,[import].[BulkException]

	Procedures: [import].[uspProcessConfirmationRequest]	returns error statuses
		,[import].[uspProcessReverseRequest]				returns error statuses

	History:
		2017-08-18 - LBD - Created
		2017-09-05 - LBD - Modified, included confirms also
		2017-10-25 - LBD - Modified, set StatusFlag according to result
*****************************************************************************************/
ALTER   PROCEDURE [import].[uspProcessPNCExceptionOld](
	 @pnvUserName NVARCHAR(100)
)
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @tblPNCException table(
		PNCExceptionId bigint
	);
	DECLARE @tblItemConfirmRequest [ifa].[ItemConfirmRequestType];
	DECLARE @iOrgId int
		,@biPNCExceptionId bigint
		,@nvProcessKey nvarchar(25)
		,@nvItemKey nvarchar(25)
		,@nvExceptionCode nvarchar(25)
		,@iStatusFlag int = 1
		,@iReverseItemStatusId int = [common].[ufnItemStatus]('Reversed')
		,@iFinalItemStatusId int = [common].[ufnItemStatus]('Final')
		,@iAcceptedClientAcceptedId  int = [common].[ufnClientAccepted]('Accepted')
		,@iErrorDetailId int
		,@iCurrentTransactionLevel int
		,@sSchemaName nvarchar(128) = N'import';

	SELECT @iOrgId = OrgId
	FROM [organization].[Org] 
	WHERE ExternalCode = 'PNCClnt';

	DECLARE csr_Reverse CURSOR FOR
	SELECT pe.PNCExceptionId,pe.ProcessKey,pe.ItemKey,et.Code
	FROM [import].[PNCException] pe
	INNER JOIN [import].[ExceptionType] et ON pe.ExceptionTypeId = et.ExceptionTypeId
	WHERE (et.Code = 'R'		--exception reversals
			OR et.Code = 'C')	--exception confirms --2017-09-05 LBD
		AND Processed = 0		--only those we haven't processed
	ORDER BY pe.PNCExceptionId;
	OPEN csr_Reverse
	FETCH csr_Reverse into @biPNCExceptionId, @nvProcessKey,@nvItemKey,@nvExceptionCode;
	WHILE @@FETCH_STATUS = 0
	BEGIN
		IF @nvExceptionCode = 'R'
			EXECUTE [import].[uspProcessReverseRequest] @pnvProcessKey=@nvProcessKey, @pnvItemKey=@nvItemKey, @piOrgId=@iOrgId, @pnvUserName=@pnvUserName, @piStatusFlag=@iStatusFlag OUTPUT;
		ELSE IF @nvExceptionCode = 'C'
		BEGIN
			--GRAB data
			INSERT INTO @tblItemConfirmRequest(ItemKey,ClientItemId,ClientAccepted,Fee,PayoutAmount)
			SELECT ItemKey,ClientItemId,@iAcceptedClientAcceptedId,Fee, Amount
			FROM [ifa].[Process] p WITH (READUNCOMMITTED)
			INNER JOIN [ifa].[Item] i WITH (READUNCOMMITTED) ON p.ProcessId = i.ProcessId
			WHERE p.ProcessKey = @nvProcessKey
				AND i.ItemKey = @nvItemKey;
			IF EXISTS (SELECT 'X' FROM @tblItemConfirmRequest)
				EXECUTE [import].[uspProcessConfirmationRequest] @pnvProcessKey=@nvProcessKey, @piOrgId=@iOrgId, @ptblItemConfirmRequest=@tblItemConfirmRequest, @pnvUserName=@pnvUserName, @piStatusFlag=@iStatusFlag OUTPUT;
			ELSE
				SET @iStatusFlag = [import].[ufnStatusFlag]('DoesntExist');
			DELETE FROM @tblItemConfirmRequest;
		END
		--UPDATE using the StatusFlag received
		UPDATE [import].[PNCException]
			SET Processed = 1
				,StatusFlag = @iStatusFlag
		WHERE PNCExceptionId = @biPNCExceptionId;

		FETCH csr_Reverse into @biPNCExceptionId, @nvProcessKey,@nvItemKey,@nvExceptionCode;
	END
END
